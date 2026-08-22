use "pony_test"
use lori = "lori"

// Pipelining, streaming, chunked send-token correlation, and close ordering
// exercised through `HTTPServer[_TestFakeBackend]`.

class \nodoc\ iso _TestPurePipelineCorrectness is UnitTest
  """
  Three pipelined GETs, responded in reverse order (2, 1, 0). The response
  queue delivers on the wire in registration order (0, 1, 2). Verified by
  finding the response bodies in the capture and checking their offsets.
  """
  fun name(): String => "pure/pipeline correctness"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPurePipelineActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPurePipelineConnectionClose is UnitTest
  """
  Two pipelined requests, second carries `Connection: close`. Both responses
  hit the wire; the second triggers a close, and a follow-up request fed
  after gets dropped.
  """
  fun name(): String => "pure/pipeline connection close"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPurePipelineCloseActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureStreamingResponse is UnitTest
  """
  A chunked response with three chunks writes chunked framing and every
  chunk body to the wire, ending with a terminal `0\r\n\r\n` chunk.
  """
  fun name(): String => "pure/streaming response"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureStreamingActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureMaxPendingOverflow is UnitTest
  """
  With `max_pending_responses' = 2`, four pipelined requests where only the
  first responds triggers HTTPServer's overflow safety net at request 3:
  a 500 Internal Server Error and connection close.
  """
  fun name(): String => "pure/max pending overflow"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    let config = ServerConfig("localhost", "0" where max_pending_responses' = 2)
    try
      let actor' = _TestPureMaxPendingActor(h, _FakeServerFd()?, config)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureHTTP10ChunkedRejection is UnitTest
  """
  `start_chunked_response` on an HTTP/1.0 responder returns
  `ChunkedNotSupported`. The actor falls back to a plain `respond`, and the
  200 with body "fallback" reaches the wire.
  """
  fun name(): String => "pure/http 1.0 chunked rejection"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureChunkedFallbackActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureChunkSentCallback is UnitTest
  """
  Streaming driven by `on_chunk_sent`: each callback drives the next
  `send_chunk`. Three chunks and their bodies all reach the wire in order.
  """
  fun name(): String => "pure/on_chunk_sent callback"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureChunkSentActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureChunkSentBeforeClose is UnitTest
  """
  One chunk on a `Connection: close` request. Every `ChunkSendToken`
  `send_chunk` returned gets exactly one matching `on_chunk_sent`.
  """
  fun name(): String => "pure/chunk sent before close"

  fun apply(h: TestHelper) =>
    _RunPureChunkCount(h, 1)

class \nodoc\ iso _TestPureChunksSentMultipleBeforeClose is UnitTest
  """Three chunks on a `Connection: close` request. Tokens match callbacks."""
  fun name(): String => "pure/multiple chunks sent before close"

  fun apply(h: TestHelper) =>
    _RunPureChunkCount(h, 3)

class \nodoc\ iso _TestPureChunkSentPipelinedNonHead is UnitTest
  """
  Two pipelined requests, second is chunked while behind the head; the
  chunk buffers, the head answers, the queue cascades. The buffered chunk's
  `on_chunk_sent` fires — one token, one callback.
  """
  fun name(): String => "pure/chunk sent on pipelined non-head response"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPurePipelinedChunkActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

primitive \nodoc\ _RunPureChunkCount
  """
  Spawn a `_TestPureChunkCountActor` bound to `h` that starts a chunked
  response, sends `n` chunks, finishes, and asserts token/callback parity.
  """
  fun apply(h: TestHelper, chunks: USize) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureChunkCountActor(h, _FakeServerFd()?, chunks)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPurePipelineActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  embed _responders: Array[Responder]
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _responders = Array[Responder]
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let requests: String val =
      "GET /0 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    let wire: String val = _capture.bytes().clone()
    try
      let p0 = wire.find("response-0")?
      let p1 = wire.find("response-1")?
      let p2 = wire.find("response-2")?
      _h.assert_true(
        (p0 < p1) and (p1 < p2),
        "responses out of order: p0=" + p0.string() +
          " p1=" + p1.string() +
          " p2=" + p2.string())
      _h.complete(true)
    else
      _h.fail("could not find all responses in:\n" + wire)
      _h.complete(false)
    end

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _responders.push(responder)
    if _responders.size() == 3 then
      try
        _respond(_responders(2)?, "response-2")
        _respond(_responders(1)?, "response-1")
        _respond(_responders(0)?, "response-0")
      end
    end

  fun ref _respond(responder: Responder, body: String val) =>
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

actor \nodoc\ _TestPurePipelineCloseActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let requests: String val =
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /2 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    let wire: String val = _capture.bytes().clone()
    _h.assert_true(
      wire.contains("body-1") and wire.contains("body-2"),
      "expected both responses; got:\n" + wire)

    // A follow-up request after Connection: close closes lands in `_Closing`
    // and gets no response.
    let extra: String val = "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(extra) end)
    let after: String val = _capture.bytes().clone()
    _h.assert_false(
      after.contains("body-3"),
      "expected no third response after close; got:\n" + after)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let path: String val = request'.uri.path
    let body: String val =
      if path == "/1" then "body-1"
      elseif path == "/2" then "body-2"
      else "body-3"
      end
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureStreamingActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let request: String val = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    let wire: String val = _capture.bytes().clone()
    _h.assert_true(
      wire.contains("Transfer-Encoding: chunked") or
        wire.contains("transfer-encoding: chunked"),
      "missing chunked header in:\n" + wire)
    _h.assert_true(
      wire.contains("chunk1") and wire.contains("chunk2") and
        wire.contains("chunk3"),
      "missing chunk bodies in:\n" + wire)
    _h.assert_true(
      wire.contains("0\r\n\r\n"),
      "missing terminal chunk in:\n" + wire)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers =
      recover val
        Headers .> set("Content-Type", "text/plain")
      end
    responder.start_chunked_response(StatusOK, headers)
    responder.send_chunk("chunk1")
    responder.send_chunk("chunk2")
    responder.send_chunk("chunk3")
    responder.finish_response()

actor \nodoc\ _TestPureMaxPendingActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _count: USize = 0

  new create(h: TestHelper, fd: U32, config: ServerConfig) =>
    _h = h
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        config)
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let requests: String val =
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /4 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    let wire: String val = _capture.bytes().clone()
    try
      let ok_pos = wire.find("first-ok")?
      let err_pos = wire.find("500 Internal Server Error")?
      _h.assert_true(
        ok_pos < err_pos,
        "200 must precede overflow 500; got:\n" + wire)
      try
        wire.find("first-ok", ok_pos + 1)?
        _h.fail("second 'first-ok' in wire: " + wire)
      end
      try
        wire.find("500 Internal Server Error", err_pos + 1)?
        _h.fail("second overflow 500 in wire: " + wire)
      end
    else
      _h.fail("wire missing 200 or overflow 500:\n" + wire)
    end
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _count = _count + 1
    if _count == 1 then
      let body: String val = "first-ok"
      let response = ResponseBuilder(StatusOK)
        .add_header("Content-Length", body.size().string())
        .finish_headers()
        .add_chunk(body)
        .build()
      responder.respond(response)
    end

actor \nodoc\ _TestPureChunkedFallbackActor is
  HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let request: String val = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    let wire: String val = _capture.bytes().clone()
    _h.assert_true(
      wire.contains("200 OK"),
      "missing 200 OK in:\n" + wire)
    _h.assert_true(
      wire.contains("fallback"),
      "missing fallback body in:\n" + wire)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers = recover val Headers .> set("Content-Type", "text/plain") end
    match \exhaustive\ responder.start_chunked_response(StatusOK, headers)
    | StreamingStarted =>
      responder.send_chunk("chunk1")
      responder.finish_response()
    | ChunkedNotSupported =>
      let body: String val = "fallback"
      let response = ResponseBuilder(StatusOK)
        .add_header("Content-Length", body.size().string())
        .finish_headers()
        .add_chunk(body)
        .build()
      responder.respond(response)
    | AlreadyResponded => None
    | ConnectionClosed => None
    end

actor \nodoc\ _TestPureChunkSentActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _responder: (Responder | None) = None
  var _chunks_started: USize = 0
  var _chunks_delivered: USize = 0

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let request: String val = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    // `_chunks_started` is the "next chunk number to send" — ends one past
    // the last chunk actually sent. Token identity is verified by
    // `_TestPureChunkCountActor`; here the point is the on_chunk_sent →
    // send_chunk cascade, which token-identity checks would defeat by
    // triggering finish_response deep inside a nested send_chunk call.
    _h.assert_eq[USize](
      4,
      _chunks_started,
      "counter should reach 4 (one past 3 sent chunks)")
    _h.assert_eq[USize](
      3,
      _chunks_delivered,
      "expected 3 on_chunk_sent callbacks")

    let wire: String val = _capture.bytes().clone()
    _h.assert_true(
      wire.contains("cs-chunk-1") and wire.contains("cs-chunk-2") and
        wire.contains("cs-chunk-3"),
      "missing chunk bodies in:\n" + wire)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers = recover val Headers .> set("Content-Type", "text/plain") end
    responder.start_chunked_response(StatusOK, headers)
    _responder = responder
    _chunks_started = 1
    responder.send_chunk("cs-chunk-1")

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    _chunks_delivered = _chunks_delivered + 1
    match _responder
    | let r: Responder =>
      _chunks_started = _chunks_started + 1
      if _chunks_started <= 3 then
        r.send_chunk("cs-chunk-" + _chunks_started.string())
      else
        r.finish_response()
        _responder = None
      end
    end

actor \nodoc\ _TestPureChunkCountActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  let _chunks: USize
  embed _sent: Array[ChunkSendToken]
  embed _delivered: Array[ChunkSendToken]
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(h: TestHelper, fd: U32, chunks: USize) =>
    _h = h
    _chunks = chunks
    _sent = Array[ChunkSendToken]
    _delivered = Array[ChunkSendToken]
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let request: String val =
      "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    _h.assert_eq[USize](
      _chunks,
      _sent.size(),
      "send_chunk should have accepted every chunk")
    _h.assert_eq[USize](
      _sent.size(),
      _delivered.size(),
      "every accepted chunk should get on_chunk_sent")
    for (i, expected) in _sent.pairs() do
      try
        _h.assert_true(
          expected == _delivered(i)?,
          "on_chunk_sent token " + i.string() +
            " should match send_chunk's return")
      else
        _h.fail("missing on_chunk_sent for chunk " + i.string())
      end
    end
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    responder.start_chunked_response(StatusOK)
    var i: USize = 0
    while i < _chunks do
      match responder.send_chunk("chunk-" + i.string())
      | let t: ChunkSendToken => _sent.push(t)
      end
      i = i + 1
    end
    responder.finish_response()

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    _delivered.push(token)

actor \nodoc\ _TestPurePipelinedChunkActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _head: (Responder | None) = None
  var _tokens: USize = 0
  var _callbacks: USize = 0

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _http =
      HTTPServer[_TestFakeBackend](
        lori.TCPServerAuth(lori.TCPListenAuth(_h.env.root)),
        fd,
        this,
        ServerConfig("localhost", "0"))
    _http._install_send_capture(_capture)
    _kick()

  fun ref _http_connection(): HTTPServer[_TestFakeBackend] => _http

  be _kick() =>
    let requests: String val =
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
        "GET /2 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    _h.assert_eq[USize](
      1,
      _tokens,
      "send_chunk should have accepted the buffered chunk")
    _h.assert_eq[USize](
      _tokens,
      _callbacks,
      "buffered chunk should still get an on_chunk_sent after cascade")
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    match \exhaustive\ _head
    | None =>
      _head = responder
    | let head: Responder =>
      responder.start_chunked_response(StatusOK)
      match responder.send_chunk("pipelined-chunk")
      | let _: ChunkSendToken => _tokens = _tokens + 1
      end
      responder.finish_response()
      _head = None
      let body: String val = "head"
      head.respond(
        ResponseBuilder(StatusOK)
          .add_header("Content-Length", body.size().string())
          .finish_headers()
          .add_chunk(body)
          .build())
    end

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    _callbacks = _callbacks + 1
