use "pony_test"
use lori = "lori"

// Backpressure integration through HTTPServer. Tests drive
// `HTTPServer._on_throttled` and `_on_unthrottled` directly rather than
// exercising lori's throttle detection, which has its own tests.

class \nodoc\ iso _TestPureOnThrottledBuffers is UnitTest
  """
  When throttle applies, the response queue buffers and no bytes reach the
  wire. Verified end to end: `on_throttled` fires on the actor; a request
  fed after throttle gets `on_request_complete`; the response the actor
  writes stays out of the send capture until unthrottle.
  """
  fun name(): String => "pure/on_throttled buffers response"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureOnThrottledActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureOnUnthrottledFlushes is UnitTest
  """
  After unthrottle, the queue flushes what it buffered and the capture
  picks up the response bytes.
  """
  fun name(): String => "pure/on_unthrottled flushes buffered response"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureOnUnthrottledActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureCloseUnderBackpressure is UnitTest
  """
  A `close` taken while throttled is a hard close: `on_closed` fires
  synchronously in the same behavior. Pins the muted-close path documented
  in lori's `TCPConnection.close()`.
  """
  fun name(): String => "pure/close under backpressure"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureCloseUnderBackpressureActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPureOnThrottledActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _throttled_fired: Bool = false

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
    _http._on_throttled()
    _h.assert_true(_throttled_fired, "on_throttled did not fire")

    let request: String val = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    _h.assert_false(
      _capture.bytes().contains("HTTP/1.1 200 OK"),
      "response should have been buffered by the queue, not sent")
    _h.complete(true)

  fun ref on_throttled() =>
    _throttled_fired = true

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureOnUnthrottledActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _unthrottled_fired: Bool = false

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
    _http._on_throttled()
    let request: String val = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)
    _h.assert_false(
      _capture.bytes().contains("HTTP/1.1 200 OK"),
      "response should still be buffered before unthrottle")

    _http._on_unthrottled()
    _h.assert_true(_unthrottled_fired, "on_unthrottled did not fire")
    _h.assert_true(
      _capture.bytes().contains("HTTP/1.1 200 OK"),
      "response should have flushed after unthrottle; got:\n" +
        _capture.bytes().clone())
    _h.complete(true)

  fun ref on_unthrottled() =>
    _unthrottled_fired = true

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureCloseUnderBackpressureActor is
  HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _closed_fired: Bool = false

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
    _http._on_throttled()
    _http.close()
    _h.assert_true(
      _closed_fired,
      "on_closed should have fired synchronously under backpressure")
    _h.complete(true)

  fun ref on_closed() =>
    _closed_fired = true
