use "pony_check"
use "pony_test"

class val _ResponseInput is Stringable
  """Test input: indices and sizes that the property uses to build a response."""
  let status_idx: USize
  let num_headers: USize
  let body_size: USize
  let use_http10: Bool

  new val create(si: USize, nh: USize, bs: USize, h10: Bool) =>
    status_idx = si
    num_headers = nh
    body_size = bs
    use_http10 = h10

  fun string(): String iso^ =>
    recover iso
      String.>append("ResponseInput(status_idx=")
        .>append(status_idx.string())
        .>append(", num_headers=")
        .>append(num_headers.string())
        .>append(", body_size=")
        .>append(body_size.string())
        .>append(", use_http10=")
        .>append(use_http10.string())
        .>append(")")
    end

class \nodoc\ iso _PropertyResponseWireFormat is Property1[_ResponseInput]
  """
  Serialized responses have valid HTTP wire format structure: status line,
  headers with `: ` separator, blank line, then body.
  """
  fun name(): String => "response_serializer/wire_format"

  fun gen(): Generator[_ResponseInput] =>
    Generators.map4[USize, USize, USize, Bool, _ResponseInput](
      Generators.usize(0, 5),
      Generators.usize(0, 5),
      Generators.usize(0, 100),
      Generators.bool(),
      {(si, nh, bs, h10) => _ResponseInput(si, nh, bs, h10) })

  fun ref property(arg1: _ResponseInput, ph: PropertyHelper) =>
    let statuses: Array[Status val] val =
      [StatusOK; StatusCreated; StatusNoContent
       StatusBadRequest; StatusNotFound
       StatusInternalServerError]

    let status = try
      statuses(arg1.status_idx % statuses.size())?
    else
      StatusOK
    end

    let version: Version =
      if arg1.use_http10 then HTTP10 else HTTP11 end

    let headers = recover val
      let h = Headers
      var i: USize = 0
      while i < arg1.num_headers do
        h.add("header-" + i.string(), "value-" + i.string())
        i = i + 1
      end
      h
    end

    let body: (ByteSeq | None) = if arg1.body_size > 0 then
      recover val
        let arr = Array[U8](arg1.body_size)
        var i: USize = 0
        while i < arg1.body_size do
          arr.push('X')
          i = i + 1
        end
        arr
      end
    else
      None
    end

    let result: Array[U8] val =
      _ResponseSerializer(status, headers, body where version = version)
    let output = String.from_array(result)

    // Verify status line starts with correct version
    let version_prefix: String val =
      if arg1.use_http10 then "HTTP/1.0 " else "HTTP/1.1 " end
    ph.assert_true(
      output.contains(version_prefix),
      "output should contain " + version_prefix)

    // Verify status code and reason appear
    let code_str: String val = status.code().string()
    ph.assert_true(
      output.contains(code_str),
      "output should contain status code " + code_str)
    ph.assert_true(
      output.contains(status.reason()),
      "output should contain reason phrase " + status.reason())

    // Verify header/body separator exists
    ph.assert_true(
      output.contains("\r\n\r\n"),
      "output should contain blank line separator")

    // Verify each header appears in output
    var i: USize = 0
    while i < arg1.num_headers do
      let expected_header: String val =
        "header-" + i.string() + ": " + "value-" + i.string() + "\r\n"
      ph.assert_true(
        output.contains(expected_header),
        "output should contain header: " + expected_header)
      i = i + 1
    end

    // Verify body size
    let sep_pos = try
      output.find("\r\n\r\n")?
    else
      ph.fail("no header/body separator found")
      return
    end
    let body_start = sep_pos + 4
    let actual_body_size = output.size() - body_start.usize()
    ph.assert_eq[USize](arg1.body_size, actual_body_size, "body size mismatch")

class \nodoc\ iso _TestResponseSerializerKnownGood is UnitTest
  """
  Verify exact byte output for known HTTP responses.
  """
  fun name(): String => "response_serializer/known_good"

  fun apply(h: TestHelper) =>
    _test_200_no_headers_no_body(h)
    _test_200_with_header_and_body(h)
    _test_404_no_body(h)
    _test_http10_200_no_body(h)

  fun _test_200_no_headers_no_body(h: TestHelper) =>
    let headers = recover val Headers end
    let result: Array[U8] val = _ResponseSerializer(StatusOK, headers)
    let expected = "HTTP/1.1 200 OK\r\n\r\n"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "200 OK, no headers, no body")

  fun _test_200_with_header_and_body(h: TestHelper) =>
    let headers = recover val
      let hd = Headers
      hd.set("content-type", "text/plain")
      hd
    end
    let body: Array[U8] val = "Hello, World!".array()
    let result: Array[U8] val =
      _ResponseSerializer(StatusOK, headers, body)
    let expected =
      "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\n\r\nHello, World!"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "200 OK with Content-Type and body")

  fun _test_404_no_body(h: TestHelper) =>
    let headers = recover val Headers end
    let result: Array[U8] val = _ResponseSerializer(StatusNotFound, headers)
    let expected = "HTTP/1.1 404 Not Found\r\n\r\n"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "404 Not Found, no body")

  fun _test_http10_200_no_body(h: TestHelper) =>
    let headers = recover val Headers end
    let result: Array[U8] val =
      _ResponseSerializer(StatusOK, headers where version = HTTP10)
    let expected = "HTTP/1.0 200 OK\r\n\r\n"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "HTTP/1.0 200 OK")
