use "format"
use "pony_check"
use "pony_test"

// ---------------------------------------------------------------------------
// Test helper: recording implementation of _RequestParserNotify
// ---------------------------------------------------------------------------

class \nodoc\ _TestParserNotify is _RequestParserNotify
  embed requests: Array[(Method, String val, Version, Headers val)] =
    Array[(Method, String val, Version, Headers val)]
  embed body_chunks: Array[Array[U8] val] = Array[Array[U8] val]
  var completed: USize = 0
  embed errors: Array[ParseError] = Array[ParseError]

  fun ref request_received(
    method: Method,
    uri: String val,
    version: Version,
    headers: Headers val)
  =>
    requests.push((method, uri, version, headers))

  fun ref body_chunk(data: Array[U8] val) =>
    body_chunks.push(data)

  fun ref request_complete() =>
    completed = completed + 1

  fun ref parse_error(err: ParseError) =>
    errors.push(err)

  fun ref collected_body_string(): String val =>
    """Concatenate all body chunks into a single string."""
    let out = String
    for chunk in body_chunks.values() do
      out.append(chunk)
    end
    out.clone()

// ---------------------------------------------------------------------------
// Property-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _PropertyValidRequestLineParsesCorrectly
  is Property1[(String val, String val)]
  """
  Valid (method, path) pairs serialized as HTTP/1.1 request lines parse
  correctly, delivering request_received with matching values and then
  request_complete.
  """
  fun name(): String => "parser/valid_request_line"

  fun gen(): Generator[(String val, String val)] =>
    // Generate (method_string, path)
    let method_gen = Generators.one_of[String val](
      ["GET"; "HEAD"; "POST"; "PUT"; "DELETE"
       "CONNECT"; "OPTIONS"; "TRACE"; "PATCH"])
    let path_gen = Generators.map2[String val, String val, String val](
      Generators.unit[String val]("/"),
      Generators.ascii_letters(0, 20),
      {(slash, rest) => slash + rest })
    Generators.zip2[String val, String val](method_gen, path_gen)

  fun ref property(
    arg1: (String val, String val),
    ph: PropertyHelper)
  =>
    (let method_str, let path) = arg1
    let raw: String val =
      method_str + " " + path + " HTTP/1.1\r\nHost: test\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    ph.assert_eq[USize](1, notify.requests.size(),
      "should have 1 request")
    ph.assert_eq[USize](1, notify.completed,
      "should have 1 completion")
    ph.assert_eq[USize](0, notify.errors.size(),
      "should have 0 errors")
    try
      (let m, let u, let v, _) = notify.requests(0)?
      ph.assert_eq[String val](method_str, m.string())
      ph.assert_eq[String val](path, u)
      ph.assert_true(v is HTTP11, "version should be HTTP/1.1")
    else
      ph.fail("could not read request")
    end

class \nodoc\ iso _PropertyInvalidMethodRejected
  is Property1[String val]
  """
  Invalid method strings in request lines produce UnknownMethod errors.
  """
  fun name(): String => "parser/invalid_method_rejected"

  fun gen(): Generator[String val] =>
    Generators.frequency[String val]([
      as WeightedGenerator[String val]:
      (1, Generators.one_of[String val](
        ["get"; "head"; "post"; "put"; "delete"
         "connect"; "options"; "trace"; "patch"]))
      (1, Generators.one_of[String val](
        ["GETX"; "POSTY"; "PUTS"]))
      (1, Generators.one_of[String val](
        ["GE"; "POS"; "DELET"]))
      (1, Generators.ascii_numeric(1, 10))
    ])

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    let raw: String val = arg1 + " / HTTP/1.1\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    ph.assert_eq[USize](0, notify.requests.size(),
      "should have 0 requests for: " + arg1)
    ph.assert_eq[USize](1, notify.errors.size(),
      "should have 1 error for: " + arg1)
    try
      ph.assert_true(notify.errors(0)? is UnknownMethod,
        "error should be UnknownMethod for: " + arg1)
    end

class \nodoc\ iso _PropertyHeadersRoundtrip
  is Property1[Array[(String val, String val)] ref]
  """
  Headers added to a request are correctly parsed and available in the
  delivered Headers collection.
  """
  fun name(): String => "parser/headers_roundtrip"

  fun gen(): Generator[Array[(String val, String val)] ref] =>
    // Generate 1-5 header (name, value) pairs
    let pair_gen = Generators.zip2[String val, String val](
      Generators.ascii_letters(1, 10),
      Generators.ascii_letters(1, 20))
    Generators.array_of[
      (String val, String val)](pair_gen, 1, 5)

  fun ref property(
    arg1: Array[(String val, String val)] ref,
    ph: PropertyHelper)
  =>
    // Build request with headers
    var raw: String val = "GET / HTTP/1.1\r\n"
    for (hdr_name, hdr_value) in arg1.values() do
      raw = raw + hdr_name + ": " + hdr_value + "\r\n"
    end
    raw = raw + "\r\n"

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    ph.assert_eq[USize](1, notify.requests.size(),
      "should have 1 request")
    try
      (_, _, _, let headers) = notify.requests(0)?
      // Headers.get returns first value for a case-insensitive name.
      // Only check the first occurrence of each name to handle collisions.
      let seen = Array[String val]
      for (hdr_name, hdr_value) in arg1.values() do
        let lower: String val = hdr_name.lower()
        var already_seen = false
        for s in seen.values() do
          if s == lower then already_seen = true; break end
        end
        if not already_seen then
          seen.push(lower)
          match headers.get(hdr_name)
          | let v: String val =>
            ph.assert_eq[String val](hdr_value, v,
              "header " + hdr_name + " mismatch")
          | None =>
            ph.fail("header " + hdr_name + " not found")
          end
        end
      end
    else
      ph.fail("could not read request")
    end

class \nodoc\ iso _PropertyFixedBodyDelivered
  is Property1[USize]
  """
  Requests with Content-Length have their body delivered completely via
  body_chunk callbacks, followed by request_complete.
  """
  fun name(): String => "parser/fixed_body_delivered"

  fun gen(): Generator[USize] =>
    Generators.usize(1, 200)

  fun ref property(arg1: USize, ph: PropertyHelper) =>
    // Build body of the given size
    let body = recover val
      let b = Array[U8](arg1)
      var i: USize = 0
      while i < arg1 do
        b.push('A' + (i % 26).u8())
        i = i + 1
      end
      b
    end

    let raw = recover val
      let r = String
      r.append("POST /data HTTP/1.1\r\n")
      r.append("Content-Length: " + arg1.string() + "\r\n")
      r.append("\r\n")
      r.append(body)
      r
    end

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    ph.assert_eq[USize](1, notify.requests.size(),
      "should have 1 request")
    ph.assert_eq[USize](1, notify.completed,
      "should have 1 completion")
    ph.assert_eq[USize](0, notify.errors.size(),
      "should have 0 errors")

    // Verify body size by summing chunks
    var total_body: USize = 0
    for chunk in notify.body_chunks.values() do
      total_body = total_body + chunk.size()
    end
    ph.assert_eq[USize](arg1, total_body, "body size mismatch")

    // Verify body content byte by byte
    var byte_idx: USize = 0
    for chunk in notify.body_chunks.values() do
      try
        var ci: USize = 0
        while ci < chunk.size() do
          ph.assert_eq[U8](body(byte_idx)?, chunk(ci)?,
            "body byte mismatch at " + byte_idx.string())
          byte_idx = byte_idx + 1
          ci = ci + 1
        end
      end
    end

class \nodoc\ iso _PropertyChunkedBodyDelivered
  is Property1[Array[USize] ref]
  """
  Chunked transfer encoding delivers the complete body and
  request_complete.
  """
  fun name(): String => "parser/chunked_body_delivered"

  fun gen(): Generator[Array[USize] ref] =>
    // Generate 1-5 chunk sizes between 1 and 50
    Generators.array_of[USize](Generators.usize(1, 50), 1, 5)

  fun ref property(arg1: Array[USize] ref, ph: PropertyHelper) =>
    // Build chunked request with known data
    var total_size: USize = 0
    var raw: String val =
      "POST /upload HTTP/1.1\r\n" +
      "Transfer-Encoding: chunked\r\n" +
      "\r\n"

    for size in arg1.values() do
      let chunk_data: String val = recover val
        let s = String(size)
        var i: USize = 0
        while i < size do
          s.push('A' + (i % 26).u8())
          i = i + 1
        end
        s
      end
      let hex_size: String val =
        Format.int[USize](size where fmt = FormatHexBare)
      raw = raw + hex_size + "\r\n" + chunk_data + "\r\n"
      total_size = total_size + size
    end
    raw = raw + "0\r\n\r\n"

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    ph.assert_eq[USize](1, notify.requests.size(),
      "should have 1 request")
    ph.assert_eq[USize](1, notify.completed,
      "should have 1 completion")
    ph.assert_eq[USize](0, notify.errors.size(),
      "should have 0 errors")

    var total_received: USize = 0
    for chunk in notify.body_chunks.values() do
      total_received = total_received + chunk.size()
    end
    ph.assert_eq[USize](total_size, total_received,
      "total body size mismatch")

class \nodoc\ iso _PropertyRequestLineBoundary
  is Property1[(String val, Bool)]
  """
  Mixed valid/invalid request lines: valid ones produce request_received,
  invalid ones produce parse_error.
  """
  fun name(): String => "parser/request_line_boundary"

  fun gen(): Generator[(String val, Bool)] =>
    let valid_gen: Generator[(String val, Bool)] =
      Generators.map2[String val, String val, (String val, Bool)](
        Generators.one_of[String val](
          ["GET"; "POST"; "PUT"; "DELETE"; "HEAD"]),
        Generators.ascii_letters(1, 10),
        {(method, path) =>
          (method + " /" + path + " HTTP/1.1\r\nHost: x\r\n\r\n", true) })

    let invalid_gen: Generator[(String val, Bool)] =
      Generators.frequency[String val]([
        as WeightedGenerator[String val]:
        (1, Generators.one_of[String val](
          ["get"; "GETX"; "POS"; "123"]))
        (1, Generators.ascii(1, 10))
      ]).map[(String val, Bool)](
        {(method) =>
          (method + " / HTTP/1.1\r\n\r\n", false) })

    Generators.frequency[(String val, Bool)]([
      as WeightedGenerator[(String val, Bool)]:
      (1, valid_gen)
      (1, invalid_gen)
    ])

  fun ref property(arg1: (String val, Bool), ph: PropertyHelper) =>
    (let raw, let should_succeed) = arg1
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    if should_succeed then
      ph.assert_eq[USize](1, notify.requests.size(),
        "valid request should parse")
      ph.assert_eq[USize](0, notify.errors.size(),
        "valid request should have no errors")
    else
      ph.assert_eq[USize](1, notify.errors.size(),
        "invalid request should produce error")
    end

// ---------------------------------------------------------------------------
// Example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestParserKnownGoodRequests is UnitTest
  """Verify exact callback sequences for well-known HTTP requests."""
  fun name(): String => "parser/known_good_requests"

  fun apply(h: TestHelper) =>
    _test_simple_get(h)
    _test_post_with_body(h)
    _test_get_with_multiple_headers(h)

  fun _test_simple_get(h: TestHelper) =>
    let raw = "GET / HTTP/1.1\r\nHost: www.example.com\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size(), "simple GET: 1 request")
    h.assert_eq[USize](1, notify.completed, "simple GET: 1 completion")
    try
      (let m, let u, let v, let hdrs) = notify.requests(0)?
      h.assert_true(m is GET, "method should be GET")
      h.assert_eq[String val]("/", u, "URI should be /")
      h.assert_true(v is HTTP11, "version should be HTTP/1.1")
      h.assert_eq[String val](
        "www.example.com",
        match hdrs.get("Host")
        | let s: String val => s
        else "" end,
        "Host header")
    else
      h.fail("simple GET: could not read request")
    end

  fun _test_post_with_body(h: TestHelper) =>
    let raw: String val =
      "POST /login HTTP/1.1\r\n" +
      "Host: example.com\r\n" +
      "Content-Length: 13\r\n" +
      "\r\n" +
      "user=testuser"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size(), "POST: 1 request")
    h.assert_eq[USize](1, notify.completed, "POST: 1 completion")
    try
      (let m, let u, _, _) = notify.requests(0)?
      h.assert_true(m is POST, "method should be POST")
      h.assert_eq[String val]("/login", u, "URI should be /login")
    else
      h.fail("POST: could not read request")
    end
    h.assert_eq[String val](
      "user=testuser",
      notify.collected_body_string(),
      "POST body")

  fun _test_get_with_multiple_headers(h: TestHelper) =>
    let raw: String val =
      "GET /page HTTP/1.1\r\n" +
      "Host: example.com\r\n" +
      "Accept: text/html\r\n" +
      "Accept-Language: en\r\n" +
      "\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size())
    try
      (_, _, _, let hdrs) = notify.requests(0)?
      h.assert_eq[USize](3, hdrs.size(), "should have 3 headers")
    else
      h.fail("could not read request")
    end

class \nodoc\ iso _TestIncrementalByteByByte is UnitTest
  """
  Feed a complete request one byte at a time. Verify the parser produces
  the same result as feeding all at once.
  """
  fun name(): String => "parser/incremental_byte_by_byte"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nHello"

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)

    // Feed one byte at a time
    var i: USize = 0
    let arr = raw.array()
    while i < arr.size() do
      try
        let byte = recover iso
          let a = Array[U8](1)
          a.push(arr(i)?)
          a
        end
        parser.parse(consume byte)
      end
      i = i + 1
    end

    h.assert_eq[USize](1, notify.requests.size(), "1 request")
    h.assert_eq[USize](1, notify.completed, "1 completion")
    h.assert_eq[USize](0, notify.errors.size(), "0 errors")
    h.assert_eq[String val](
      "Hello",
      notify.collected_body_string(),
      "body should be Hello")

class \nodoc\ iso _TestPipelining is UnitTest
  """Two GET requests back-to-back in one buffer — both parsed in order."""
  fun name(): String => "parser/pipelining"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "GET /first HTTP/1.1\r\nHost: test\r\n\r\n" +
      "GET /second HTTP/1.1\r\nHost: test\r\n\r\n"

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](2, notify.requests.size(), "2 requests")
    h.assert_eq[USize](2, notify.completed, "2 completions")
    try
      h.assert_eq[String val]("/first", notify.requests(0)?._2)
      h.assert_eq[String val]("/second", notify.requests(1)?._2)
    else
      h.fail("could not read requests")
    end

class \nodoc\ iso _TestPipeliningWithBody is UnitTest
  """Two requests, first with Content-Length body — both parsed correctly."""
  fun name(): String => "parser/pipelining_with_body"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST /data HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc" +
      "GET /next HTTP/1.1\r\nHost: test\r\n\r\n"

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](2, notify.requests.size(), "2 requests")
    h.assert_eq[USize](2, notify.completed, "2 completions")
    try
      (let m1, let u1, _, _) = notify.requests(0)?
      h.assert_true(m1 is POST, "first is POST")
      h.assert_eq[String val]("/data", u1)

      (let m2, let u2, _, _) = notify.requests(1)?
      h.assert_true(m2 is GET, "second is GET")
      h.assert_eq[String val]("/next", u2)
    else
      h.fail("could not read requests")
    end

class \nodoc\ iso _TestPipeliningChunked is UnitTest
  """Two requests, first chunked — both parsed correctly."""
  fun name(): String => "parser/pipelining_chunked"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST /upload HTTP/1.1\r\n" +
      "Transfer-Encoding: chunked\r\n\r\n" +
      "5\r\nHello\r\n0\r\n\r\n" +
      "GET /done HTTP/1.1\r\nHost: test\r\n\r\n"

    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](2, notify.requests.size(), "2 requests")
    h.assert_eq[USize](2, notify.completed, "2 completions")
    h.assert_eq[String val](
      "Hello", notify.collected_body_string())

class \nodoc\ iso _TestSizeLimitRequestLine is UnitTest
  """Request line exceeding small limit → TooLarge."""
  fun name(): String => "parser/size_limit_request_line"

  fun apply(h: TestHelper) =>
    let config = _ParserConfig(where max_request_line_size' = 16)
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify, config)

    // "GET /very-long-path HTTP/1.1" is longer than 16 bytes
    let raw = "GET /very-long-path HTTP/1.1\r\n\r\n"
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is TooLarge, "should be TooLarge")
    end

class \nodoc\ iso _TestSizeLimitHeaders is UnitTest
  """Headers exceeding small limit → TooLarge."""
  fun name(): String => "parser/size_limit_headers"

  fun apply(h: TestHelper) =>
    let config = _ParserConfig(where max_header_size' = 32)
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify, config)

    let raw: String val =
      "GET / HTTP/1.1\r\n" +
      "X-Very-Long-Header-Name: very-long-value-that-exceeds-limit\r\n" +
      "\r\n"
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is TooLarge, "should be TooLarge")
    end

class \nodoc\ iso _TestSizeLimitBody is UnitTest
  """Content-Length or chunked body exceeding small limit → BodyTooLarge."""
  fun name(): String => "parser/size_limit_body"

  fun apply(h: TestHelper) =>
    let config = _ParserConfig(where max_body_size' = 5)

    // Fixed body: Content-Length 10 > max_body_size 5
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify, config)
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Content-Length: 10\r\n\r\n" +
      "0123456789"
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(),
      "fixed body: should have 1 error")
    try
      h.assert_true(notify.errors(0)? is BodyTooLarge,
        "fixed body: should be BodyTooLarge")
    end

    // Chunked body: 10 bytes > max_body_size 5
    let notify2: _TestParserNotify ref = _TestParserNotify
    let parser2 = _RequestParser(notify2, config)
    let raw2: String val =
      "POST / HTTP/1.1\r\n" +
      "Transfer-Encoding: chunked\r\n\r\n" +
      "a\r\n0123456789\r\n0\r\n\r\n"
    parser2.parse(recover raw2.array().clone() end)

    h.assert_eq[USize](1, notify2.errors.size(),
      "chunked body: should have 1 error")
    try
      h.assert_true(notify2.errors(0)? is BodyTooLarge,
        "chunked body: should be BodyTooLarge")
    end

class \nodoc\ iso _TestInvalidContentLength is UnitTest
  """Non-numeric Content-Length → InvalidContentLength."""
  fun name(): String => "parser/invalid_content_length"

  fun apply(h: TestHelper) =>
    let raw = "POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is InvalidContentLength,
        "should be InvalidContentLength")
    end

class \nodoc\ iso _TestInvalidChunkSize is UnitTest
  """Non-hex chunk size → InvalidChunk."""
  fun name(): String => "parser/invalid_chunk_size"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Transfer-Encoding: chunked\r\n\r\n" +
      "xyz\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is InvalidChunk,
        "should be InvalidChunk")
    end

class \nodoc\ iso _TestMissingCRLFAfterChunk is UnitTest
  """Wrong bytes after chunk data → InvalidChunk."""
  fun name(): String => "parser/missing_crlf_after_chunk"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Transfer-Encoding: chunked\r\n\r\n" +
      "5\r\nHelloXX"  // Missing CRLF after "Hello", has "XX" instead
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is InvalidChunk,
        "should be InvalidChunk")
    end

class \nodoc\ iso _TestChunkedWithTrailers is UnitTest
  """Chunked request with trailer headers → trailers skipped, completes."""
  fun name(): String => "parser/chunked_with_trailers"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Transfer-Encoding: chunked\r\n\r\n" +
      "5\r\nHello\r\n" +
      "0\r\n" +
      "Trailer-Header: value\r\n" +
      "\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size(), "1 request")
    h.assert_eq[USize](1, notify.completed, "1 completion")
    h.assert_eq[USize](0, notify.errors.size(), "0 errors")
    h.assert_eq[String val](
      "Hello", notify.collected_body_string())

class \nodoc\ iso _TestHTTP10Version is UnitTest
  """HTTP/1.0 request → version is HTTP10."""
  fun name(): String => "parser/http10_version"

  fun apply(h: TestHelper) =>
    let raw = "GET / HTTP/1.0\r\nHost: test\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size())
    try
      h.assert_true(notify.requests(0)?._3 is HTTP10,
        "version should be HTTP/1.0")
    end

class \nodoc\ iso _TestInvalidVersion is UnitTest
  """Bad version string → InvalidVersion."""
  fun name(): String => "parser/invalid_version"

  fun apply(h: TestHelper) =>
    _test_version(h, "HTTP/2.0")
    _test_version(h, "HTTP/1.2")
    _test_version(h, "HTXP/1.1")
    _test_version(h, "HTTP/1")

  fun _test_version(h: TestHelper, ver: String val) =>
    let raw: String val = "GET / " + ver + "\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)
    h.assert_eq[USize](1, notify.errors.size(),
      "should have 1 error for " + ver)
    try
      h.assert_true(notify.errors(0)? is InvalidVersion,
        "should be InvalidVersion for " + ver)
    end

class \nodoc\ iso _TestNoBody is UnitTest
  """
  GET request with no Content-Length or Transfer-Encoding →
  request_complete immediately after headers.
  """
  fun name(): String => "parser/no_body"

  fun apply(h: TestHelper) =>
    let raw = "GET / HTTP/1.1\r\nHost: test\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size(), "1 request")
    h.assert_eq[USize](1, notify.completed, "1 completion")
    h.assert_eq[USize](0, notify.body_chunks.size(), "0 body chunks")

class \nodoc\ iso _TestContentLengthZero is UnitTest
  """Content-Length: 0 → request_complete immediately (no body state)."""
  fun name(): String => "parser/content_length_zero"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Content-Length: 0\r\n" +
      "\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size(), "1 request")
    h.assert_eq[USize](1, notify.completed, "1 completion")
    h.assert_eq[USize](0, notify.body_chunks.size(), "0 body chunks")

class \nodoc\ iso _TestContentLengthAndChunked is UnitTest
  """
  Both Content-Length and Transfer-Encoding: chunked → chunked takes
  precedence per RFC 7230 §3.3.3.
  """
  fun name(): String => "parser/content_length_and_chunked"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Content-Length: 100\r\n" +
      "Transfer-Encoding: chunked\r\n" +
      "\r\n" +
      "5\r\nHello\r\n0\r\n\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.requests.size(), "1 request")
    h.assert_eq[USize](1, notify.completed, "1 completion")
    h.assert_eq[USize](0, notify.errors.size(), "0 errors")
    // Body is 5 bytes (chunked), not 100 (Content-Length)
    h.assert_eq[String val](
      "Hello", notify.collected_body_string())

class \nodoc\ iso _TestDuplicateContentLength is UnitTest
  """Two Content-Length headers with differing values → InvalidContentLength."""
  fun name(): String => "parser/duplicate_content_length"

  fun apply(h: TestHelper) =>
    let raw: String val =
      "POST / HTTP/1.1\r\n" +
      "Content-Length: 10\r\n" +
      "Content-Length: 20\r\n" +
      "\r\n"
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is InvalidContentLength,
        "should be InvalidContentLength")
    end

class \nodoc\ iso _TestInvalidURI is UnitTest
  """URI with control characters → InvalidURI."""
  fun name(): String => "parser/invalid_uri"

  fun apply(h: TestHelper) =>
    // URI with control character (0x01) → InvalidURI
    let raw: String val = recover val
      let s = String
      s.append("GET /foo")
      s.push(0x01)
      s.append("bar HTTP/1.1\r\n\r\n")
      s
    end
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(),
      "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is InvalidURI,
        "should be InvalidURI")
    end

class \nodoc\ iso _TestDataAfterError is UnitTest
  """
  Feed data after a parse error → no additional callbacks fired
  (verifies _failed short-circuit).
  """
  fun name(): String => "parser/data_after_error"

  fun apply(h: TestHelper) =>
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)

    // Cause an error
    let bad = "INVALID / HTTP/1.1\r\n\r\n"
    parser.parse(recover bad.array().clone() end)
    h.assert_eq[USize](1, notify.errors.size(), "1 error after bad request")

    // Feed valid data after error
    let good = "GET / HTTP/1.1\r\nHost: test\r\n\r\n"
    parser.parse(recover good.array().clone() end)

    // Should still have exactly 1 error and 0 requests
    h.assert_eq[USize](1, notify.errors.size(),
      "still 1 error after second parse")
    h.assert_eq[USize](0, notify.requests.size(),
      "0 requests (parser is failed)")
