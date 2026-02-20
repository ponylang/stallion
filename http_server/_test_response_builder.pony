use "pony_check"
use "pony_test"

class \nodoc\ iso _PropertyBuilderMatchesSerializer
  is Property1[_ResponseInput]
  """
  ResponseBuilder produces identical output to _ResponseSerializer for
  the same status, headers, and body.
  """
  fun name(): String => "response_builder/matches_serializer"

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

    let body: (Array[U8] val | None) = if arg1.body_size > 0 then
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

    // Build with _ResponseSerializer
    let serialized: Array[U8] val =
      _ResponseSerializer(status, headers, body where version = version)

    // Build with ResponseBuilder
    var builder: ResponseHeadersBuilder =
      ResponseBuilder(status where version = version)
    for (hdr_name, hdr_value) in headers.values() do
      builder = builder.add_header(hdr_name, hdr_value)
    end
    var body_builder: ResponseBodyBuilder = builder.finish_headers()
    match body
    | let b: Array[U8] val => body_builder = body_builder.add_chunk(b)
    end
    let built: Array[U8] val = body_builder.build()

    ph.assert_eq[String val](
      String.from_array(serialized),
      String.from_array(built),
      "builder should produce same output as serializer")

class \nodoc\ iso _TestResponseBuilderKnownGood is UnitTest
  """
  Verify exact byte output for known HTTP responses built with
  ResponseBuilder.
  """
  fun name(): String => "response_builder/known_good"

  fun apply(h: TestHelper) =>
    _test_200_no_headers_no_body(h)
    _test_200_with_header_and_body(h)
    _test_404_no_body(h)
    _test_http10_version(h)

  fun _test_200_no_headers_no_body(h: TestHelper) =>
    let result = ResponseBuilder(StatusOK)
      .finish_headers()
      .build()
    let expected = "HTTP/1.1 200 OK\r\n\r\n"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "200 OK, no headers, no body")

  fun _test_200_with_header_and_body(h: TestHelper) =>
    let result = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .finish_headers()
      .add_chunk("Hello, World!")
      .build()
    let expected =
      "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\n\r\nHello, World!"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "200 OK with Content-Type and body")

  fun _test_404_no_body(h: TestHelper) =>
    let result = ResponseBuilder(StatusNotFound)
      .finish_headers()
      .build()
    let expected = "HTTP/1.1 404 Not Found\r\n\r\n"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "404 Not Found, no body")

  fun _test_http10_version(h: TestHelper) =>
    let result = ResponseBuilder(StatusOK where version = HTTP10)
      .finish_headers()
      .build()
    let expected = "HTTP/1.0 200 OK\r\n\r\n"
    h.assert_eq[String val](
      expected,
      String.from_array(result),
      "HTTP/1.0 200 OK")

class \nodoc\ iso _TestRespond is UnitTest
  """
  Verify that Responder.respond() sends raw bytes through the queue
  and marks the response as complete.
  """
  fun name(): String => "responder/respond"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)
    let id = queue.register(true)

    let raw: String val =
      "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
    let responder = Responder._create(queue, id, HTTP11)
    responder.respond(raw)

    // Verify data was flushed
    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](1, flushed.size(), "expected 1 flush")
    try
      h.assert_eq[String val](raw, flushed(0)?,
        "flushed data should match raw input")
    else
      h.fail("Flush index out of bounds")
    end

    // Verify response was completed
    h.assert_eq[USize](1, notify.completions.size(),
      "expected 1 completion")
    h.assert_eq[USize](0, queue.pending(),
      "queue should have no pending entries")

class \nodoc\ iso _TestRespondIgnoredAfterFirst is UnitTest
  """
  Verify that a second respond() is silently ignored after the first
  has already been called.
  """
  fun name(): String => "responder/respond_ignored_after_first"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)
    let id = queue.register(true)

    let responder = Responder._create(queue, id, HTTP11)
    responder.respond("HTTP/1.1 200 OK\r\n\r\nfirst")

    // Second call via respond should be silently ignored
    responder.respond("HTTP/1.1 200 OK\r\n\r\nsecond")

    // Only the first response should have been sent
    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](1, flushed.size(),
      "only first response should flush")
    h.assert_eq[USize](1, notify.completions.size(),
      "only one completion should fire")
