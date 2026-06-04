use "pony_test"

// ---------------------------------------------------------------------------
// Framing & incremental coverage (Discussion #123 §1d).
//
// A conformance corpus has no MUST-vector for keep-alive / pipelining / partial
// input, so a rewrite could regress resumability or shift a completion point
// and nothing would fail. These tests close that gap:
//   - parse-split invariance: a request fed in any chunking parses identically
//     to the single-shot result (locks resumability at every byte boundary).
//   - completion-point pins: request_complete fires at exactly one place per
//     framing, and not before.
//   - max_chunk_header_size: the one _ParserConfig limit with no prior test.
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestParseSplitInvariance is UnitTest
  """
  Feeding a well-formed request in fixed-size chunks (down to byte-by-byte)
  yields the same observable result as a single-shot parse.
  """
  fun name(): String => "parser/parse_split_invariance"

  fun apply(h: TestHelper) =>
    let requests =
      [ "GET / HTTP/1.1\r\nHost: a\r\n\r\n"
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\nhello"
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
          "5\r\n01234\r\n0\r\n\r\n"
        "GET /1 HTTP/1.1\r\nHost: a\r\n\r\nGET /2 HTTP/1.1\r\nHost: a\r\n\r\n"
      ]
    for raw in requests.values() do
      let single = _Signature.of(raw, raw.size())
      for chunk_size in [as USize: 1; 2; 3; 5; 8; 13].values() do
        let split = _Signature.of(raw, chunk_size)
        if not single.eq(split) then
          h.fail("split invariance broken at chunk_size=" +
            chunk_size.string() + " for request: " + raw +
            "\n  single-shot: " + single.show() +
            "\n  chunked:     " + split.show())
        end
      end
    end

class \nodoc\ val _Signature
  """The observable result of a parse, for equality comparison across splits."""
  let requests: USize
  let completed: USize
  let errors: USize
  let body: String

  new val create(
    requests': USize,
    completed': USize,
    errors': USize,
    body': String)
  =>
    requests = requests'
    completed = completed'
    errors = errors'
    body = body'

  new val of(raw: String, chunk_size: USize) =>
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    let bytes: Array[U8] val = raw.array()
    let step = chunk_size.max(1)
    var i: USize = 0
    while i < bytes.size() do
      let stop = (i + step).min(bytes.size())
      let seg = recover iso Array[U8](stop - i) end
      var j = i
      while j < stop do
        try seg.push(bytes(j)?) end
        j = j + 1
      end
      parser.parse(consume seg)
      i = stop
    end
    requests = notify.requests.size()
    completed = notify.completed
    errors = notify.errors.size()
    body = notify.collected_body_string()

  fun eq(other: _Signature): Bool =>
    (requests == other.requests) and (completed == other.completed)
      and (errors == other.errors) and (body == other.body)

  fun show(): String =>
    "requests=" + requests.string() + " completed=" + completed.string() +
    " errors=" + errors.string() + " body='" + body + "'"

class \nodoc\ iso _TestCompletionPoints is UnitTest
  """
  request_complete fires at exactly one place per framing, and not before:
  no-body right after the blank line; fixed body when the last byte arrives;
  chunked at the empty trailer line.
  """
  fun name(): String => "parser/completion_points"

  fun apply(h: TestHelper) =>
    // No body: completes only once the blank line's final LF arrives.
    _step(h, "no-body",
      "GET / HTTP/1.1\r\nHost: a\r\n\r", 0,
      "\n", 1)

    // Fixed body: completes only when the final body byte arrives.
    _step(h, "fixed-body",
      "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\n\r\nab", 0,
      "c", 1)

    // Chunked: completes only at the empty trailer line.
    _step(h, "chunked",
      "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
      "5\r\n01234\r\n0\r\n", 0,
      "\r\n", 1)

  fun _step(
    h: TestHelper,
    label: String,
    before: String,
    expected_before: USize,
    rest: String,
    expected_after: USize)
  =>
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover before.array().clone() end)
    h.assert_eq[USize](expected_before, notify.completed,
      label + ": completions before final bytes")
    parser.parse(recover rest.array().clone() end)
    h.assert_eq[USize](expected_after, notify.completed,
      label + ": completions after final bytes")

class \nodoc\ iso _TestSizeLimitChunkHeader is UnitTest
  """Chunk-size line (with extension) exceeding max_chunk_header_size → reject."""
  fun name(): String => "parser/size_limit_chunk_header"

  fun apply(h: TestHelper) =>
    let config = _ParserConfig(where max_chunk_header_size' = 8)
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify, config)
    // Chunk header "5;aaaaaaaaaaaa" is 14 bytes > 8.
    let raw: String val =
      "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
      "5;aaaaaaaaaaaa\r\n01234\r\n0\r\n\r\n"
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is InvalidChunk, "should be InvalidChunk")
    end

class \nodoc\ iso _TestSizeLimitHeadersCumulative is UnitTest
  """
  Many individually-small, individually-valid header lines that together exceed
  max_header_size → TooLarge. The per-line _LineScan cap can't catch this; the
  cumulative budget must (a DoS bound, not exercised by the single-oversized-line
  size test).
  """
  fun name(): String => "parser/size_limit_headers_cumulative"

  fun apply(h: TestHelper) =>
    let config = _ParserConfig(where max_header_size' = 20)
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify, config)
    // Each "A: b\r\n" is 6 bytes; five of them is 30 > 20, but no single line
    // exceeds the limit.
    let raw: String val =
      "GET / HTTP/1.1\r\nA: b\r\nA: b\r\nA: b\r\nA: b\r\nA: b\r\n\r\n"
    parser.parse(recover raw.array().clone() end)

    h.assert_eq[USize](1, notify.errors.size(), "should have 1 error")
    try
      h.assert_true(notify.errors(0)? is TooLarge, "should be TooLarge")
    end
