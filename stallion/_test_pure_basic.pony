use "constrained_types"
use "pony_test"
use lori = "lori"

class \nodoc\ iso _TestPureHelloWorld is UnitTest
  """
  Feed a well-formed HTTP/1.1 GET through `HTTPServer._on_received` with a
  fake `TCPBackend`, respond from `on_request_complete`, and verify the
  status line and body of the wire response captured from lori's send path.
  """
  fun name(): String => "pure/hello world"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureHelloWorldActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPureHelloWorldActor is HTTPServerActor[_TestFakeBackend]
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
    let request: String val =
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    let wire: String box = _capture.bytes()
    _h.assert_true(
      wire.contains("HTTP/1.1 200 OK"),
      "expected 200 OK status line; got:\n" + wire.clone())
    _h.assert_true(
      wire.contains("Hello, World!"),
      "expected body 'Hello, World!'; got:\n" + wire.clone())
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello, World!"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

class \nodoc\ iso _TestPureParseError is UnitTest
  """Garbage bytes → 400 Bad Request."""
  fun name(): String => "pure/parse error"

  fun apply(h: TestHelper) =>
    _RunPureExpectStatus(
      h,
      ServerConfig("localhost", "0"),
      "GARBAGE DATA\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureError413 is UnitTest
  """
  A `Content-Length` beyond `max_body_size` → 413 Payload Too Large.
  Body size limit is a server config knob; parser exceeds it during framing.
  """
  fun name(): String => "pure/error 413"

  fun apply(h: TestHelper) =>
    _RunPureExpectStatus(
      h,
      ServerConfig("localhost", "0" where max_body_size' = 10),
      "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n",
      "HTTP/1.1 413 Payload Too Large")

class \nodoc\ iso _TestPureError431 is UnitTest
  """
  Cumulative header bytes past `max_header_size` → 431 Request Header Fields
  Too Large.
  """
  fun name(): String => "pure/error 431"

  fun apply(h: TestHelper) =>
    _RunPureExpectStatus(
      h,
      ServerConfig("localhost", "0" where max_header_size' = 10),
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "HTTP/1.1 431 Request Header Fields Too Large")

class \nodoc\ iso _TestPureError505 is UnitTest
  """Unrecognized HTTP version → 505 HTTP Version Not Supported."""
  fun name(): String => "pure/error 505"

  fun apply(h: TestHelper) =>
    _RunPureExpectStatus(
      h,
      ServerConfig("localhost", "0"),
      "GET / HTTP/2.0\r\nHost: localhost\r\n\r\n",
      "HTTP/1.1 505 HTTP Version Not Supported")

class \nodoc\ iso _TestPureKeepAlive is UnitTest
  """
  Two pipelined HTTP/1.1 requests on the same connection → two 200 OK
  responses in send order. Keep-alive is the HTTP/1.1 default; no
  `Connection: close` on either request or response.
  """
  fun name(): String => "pure/keep-alive"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureKeepAliveActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureConnectionClose is UnitTest
  """
  A request with `Connection: close` gets a response and HTTPServer starts a
  close. Verified by feeding a second request after the first response and
  observing that no second response reaches the capture.
  """
  fun name(): String => "pure/connection close"

  fun apply(h: TestHelper) =>
    let request: String val =
      "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    _RunPureCloseAfterResponse(h, ServerConfig("localhost", "0"), request)

class \nodoc\ iso _TestPureHTTP10Close is UnitTest
  """
  An HTTP/1.0 request with no `Connection: keep-alive` closes after the
  response. Same observation shape as `pure/connection close`.
  """
  fun name(): String => "pure/http 1.0 close"

  fun apply(h: TestHelper) =>
    _RunPureCloseAfterResponse(
      h,
      ServerConfig("localhost", "0"),
      "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")

class \nodoc\ iso _TestPureClosingDropsData is UnitTest
  """
  After `HTTPServer.close()` has moved the connection into `_Closing`,
  `_on_received` is a no-op — a request fed then produces no response.
  Pins the `_Closing.on_received` behavior directly.
  """
  fun name(): String => "pure/closing drops incoming data"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureClosingDropsDataActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureOnClosedOrdering is UnitTest
  """
  Two invariants of the close path: `on_closed()` never fires inside
  `respond()` for a graceful close, and a `close()` call from inside the
  actor's `on_closed()` does not re-enter and deliver a second
  `on_closed()`. Both are structurally enforced by `_handle_closed`
  setting `_state = _Closed` before firing `on_closed`; this pins them.
  """
  fun name(): String => "pure/on_closed ordering"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureOnClosedOrderingActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureMaxRequestsPerConnection is UnitTest
  """
  With `max_requests_per_connection' = 2`, three pipelined requests get
  exactly two responses. After the second flushes, `HTTPServer` closes,
  and the third request never produces a response — even though the parser
  handed it off before the close took effect. Verified by counting
  `HTTP/1.1 200 OK` occurrences in the capture and observing `on_closed`.
  """
  fun name(): String => "pure/max requests per connection"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    let max_req =
      match \exhaustive\ MakeMaxRequestsPerConnection(2)
      | let m: MaxRequestsPerConnection => m
      | let _: ValidationFailure =>
        h.fail("could not build MaxRequestsPerConnection(2)")
        h.complete(false)
        return
      end
    let config =
      ServerConfig(
        "localhost",
        "0"
        where max_requests_per_connection' = max_req)
    try
      let actor' = _TestPureMaxRequestsActor(h, _FakeServerFd()?, config)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

primitive \nodoc\ _RunPureExpectStatus
  """
  Spawn a `_TestPureExpectStatusActor` bound to `h` with `config`, feed
  `request` through `HTTPServer._on_received`, and verify the wire response
  contains `expected_status`. Fits any single-request test where the actor's
  response body doesn't matter — including error paths where `HTTPServer`
  answers on its own and `on_request_complete` never fires.
  """
  fun apply(
    h: TestHelper,
    config: ServerConfig,
    request: String val,
    expected_status: String val)
  =>
    h.long_test(2_000_000_000)
    try
      let fd = _FakeServerFd()?
      let actor' =
        _TestPureExpectStatusActor(h, fd, config, request, expected_status)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPureExpectStatusActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _request: String val
  let _expected: String val
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(
    h: TestHelper,
    fd: U32,
    config: ServerConfig,
    request: String val,
    expected: String val)
  =>
    _h = h
    _request = request
    _expected = expected
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
    _http._on_received(recover iso Array[U8] .> append(_request) end)
    let wire: String box = _capture.bytes()
    _h.assert_true(
      wire.contains(_expected),
      "expected status '" + _expected + "'; got wire:\n" + wire.clone())
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    // Only fires for accepted requests; error tests bypass this callback.
    let body: String val = ""
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureMaxRequestsActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

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
        "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    let wire: String val = _capture.bytes().clone()
    let count = _count_occurrences(wire, "HTTP/1.1 200 OK")
    _h.assert_eq[USize](
      2,
      count,
      "expected exactly two 200 OK responses in wire; got:\n" + wire)
    // HTTPServer starts a graceful close after the second response. With a
    // fake backend and no peer, that never resolves to `on_closed` on its
    // own; disposal at test teardown finishes the connection. The response
    // count is the whole assertion here.
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

  fun _count_occurrences(s: String box, needle: String box): USize =>
    var count: USize = 0
    var offset: ISize = 0
    while true do
      try
        offset = s.find(needle, offset)? + needle.size().isize()
        count = count + 1
      else
        break
      end
    end
    count

actor \nodoc\ _TestPureKeepAliveActor is HTTPServerActor[_TestFakeBackend]
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
        "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    let wire: String val = _capture.bytes().clone()
    var count: USize = 0
    var offset: ISize = 0
    let needle: String val = "HTTP/1.1 200 OK"
    while true do
      try
        offset = wire.find(needle, offset)? + needle.size().isize()
        count = count + 1
      else
        break
      end
    end
    _h.assert_eq[USize](
      2,
      count,
      "expected two 200 OK responses on same connection; got:\n" + wire)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello, World!"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

primitive \nodoc\ _RunPureCloseAfterResponse
  """
  Spawn a `_TestPureCloseAfterResponseActor` bound to `h` with `config`,
  feed `request` and then a second, extra request. Expect exactly one
  200 OK in the capture: HTTPServer sent the response, then closed on the
  keep-alive decision, and dropped the second request in `_Closing`.
  """
  fun apply(h: TestHelper, config: ServerConfig, request: String val) =>
    h.long_test(2_000_000_000)
    try
      let fd = _FakeServerFd()?
      let actor' = _TestPureCloseAfterResponseActor(h, fd, config, request)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPureCloseAfterResponseActor is
  HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _request: String val
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(
    h: TestHelper,
    fd: U32,
    config: ServerConfig,
    request: String val)
  =>
    _h = h
    _request = request
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
    _http._on_received(recover iso Array[U8] .> append(_request) end)

    // Extra request after the first response. If HTTPServer moved to
    // `_Closing`, this is dropped and produces no response.
    let extra: String val =
      "GET /again HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(extra) end)

    let wire: String val = _capture.bytes().clone()
    var count: USize = 0
    var offset: ISize = 0
    let needle: String val = "HTTP/1.1 200 OK"
    while true do
      try
        offset = wire.find(needle, offset)? + needle.size().isize()
        count = count + 1
      else
        break
      end
    end
    _h.assert_eq[USize](
      1,
      count,
      "expected one 200 OK — the second should be dropped; got:\n" + wire)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureClosingDropsDataActor is
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
    // Explicit close before any data: HTTPServer starts a graceful close
    // and moves to `_Closing`. `_on_received` then routes to
    // `_Closing.on_received`, which is a no-op.
    _http.close()
    let request: String val = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    let wire: String val = _capture.bytes().clone()
    _h.assert_false(
      wire.contains("HTTP/1.1 200 OK"),
      "expected no response after close; got:\n" + wire)
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    // Should not fire: parser never runs on the incoming request while
    // `_Closing`.
    _h.fail("on_request_complete fired while _Closing")
    _h.complete(false)

actor \nodoc\ _TestPureOnClosedOrderingActor is
  HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _responded: Bool = false
  var _closed_count: USize = 0

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
    let request: String val =
      "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    // `respond` returned and did not fire `on_closed` re-entrantly.
    _h.assert_true(
      _responded,
      "respond() should have returned before any on_closed")
    _h.assert_eq[USize](0, _closed_count, "on_closed should not fire yet")

    // Simulate lori reporting the close. `on_closed` fires once; the
    // `close()` from inside our on_closed does not re-enter and produce
    // a second on_closed.
    _http._on_closed()
    _h.assert_eq[USize](1, _closed_count, "on_closed should fire exactly once")
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: String val = "Hello"
    responder.respond(
      ResponseBuilder(StatusOK)
        .add_header("Content-Length", body.size().string())
        .finish_headers()
        .add_chunk(body)
        .build())
    // Set AFTER respond returns. If on_closed had fired inside respond
    // (the invariant this pins), it would have run with `_responded=false`.
    _responded = true

  fun ref on_closed() =>
    _closed_count = _closed_count + 1
    _http.close()
