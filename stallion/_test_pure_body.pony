use "pony_test"
use lori = "lori"
use uri = "uri"

// Request-body accumulation, URI parsing, and cookie parsing exercised
// through `HTTPServer[_TestFakeBackend]`.

class \nodoc\ iso _TestPureURIParsing is UnitTest
  """
  A GET with path and query-string parses into `Request.uri` with the path
  and query populated.
  """
  fun name(): String => "pure/uri parsing"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureURIParsingActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureConnectURIParsing is UnitTest
  """
  A CONNECT request parses into a `URIAuthority` with host and port and an
  empty path — authority-form.
  """
  fun name(): String => "pure/connect uri parsing"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureConnectURIParsingActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureBody is UnitTest
  """
  A POST with a Content-Length body delivers the body via `on_body_chunk`
  before `on_request_complete` fires.
  """
  fun name(): String => "pure/body"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureBodyActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureNoBody is UnitTest
  """
  A GET has no body — `on_body_chunk` never fires; `on_request_complete`
  fires once.
  """
  fun name(): String => "pure/no body"

  fun apply(h: TestHelper) =>
    _RunPureNoBody(h, "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

class \nodoc\ iso _TestPureContentLengthZero is UnitTest
  """
  A POST with `Content-Length: 0` delivers no body chunks; same shape as
  no body.
  """
  fun name(): String => "pure/content-length zero"

  fun apply(h: TestHelper) =>
    _RunPureNoBody(
      h,
      "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")

class \nodoc\ iso _TestPurePipelinedBodies is UnitTest
  """
  Two pipelined POSTs each with their own body. Each request's body chunks
  reach `on_body_chunk` before that request's `on_request_complete`; the
  bodies do not bleed across requests.
  """
  fun name(): String => "pure/pipelined bodies"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPurePipelinedBodiesActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

class \nodoc\ iso _TestPureCookieParsing is UnitTest
  """
  A `Cookie` header on the request parses into `Request.cookies`, keyed by
  name.
  """
  fun name(): String => "pure/cookie parsing"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureCookieParsingActor(h, _FakeServerFd()?)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

primitive \nodoc\ _RunPureNoBody
  """
  Spawn an actor that feeds `request` and asserts no body chunks arrived
  while `on_request_complete` still fired.
  """
  fun apply(h: TestHelper, request: String val) =>
    h.long_test(2_000_000_000)
    try
      let actor' = _TestPureNoBodyActor(h, _FakeServerFd()?, request)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPureURIParsingActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _seen_path: String val = ""
  var _seen_query: String val = ""

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
      "GET /hello?name=test HTTP/1.1\r\nHost: localhost\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    _h.assert_eq[String](
      "/hello", _seen_path, "path did not parse as expected")
    _h.assert_eq[String](
      "name=test", _seen_query, "query did not parse as expected")
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _seen_path = request'.uri.path
    _seen_query =
      match \exhaustive\ request'.uri.query
      | let q: String val => q
      | None => ""
      end
    _minimal_response(responder)

  fun ref _minimal_response(responder: Responder) =>
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureConnectURIParsingActor is
  HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _seen_host: String val = ""
  var _seen_port: String val = ""
  var _seen_path: String val = ""

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
      "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    _h.assert_eq[String]("example.com", _seen_host, "authority host mismatch")
    _h.assert_eq[String]("443", _seen_port, "authority port mismatch")
    _h.assert_eq[String]("", _seen_path, "authority-form path should be empty")
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    match request'.uri.authority
    | let a: uri.URIAuthority val =>
      _seen_host = a.host
      _seen_port =
        match \exhaustive\ a.port
        | let p: U16 => p.string()
        | None => ""
        end
    end
    _seen_path = request'.uri.path
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureBodyActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _body: Array[U8] iso = recover iso Array[U8] end
  var _completes: USize = 0

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
      "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n" +
        "Hello, Body!\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    _h.assert_eq[USize](1, _completes, "on_request_complete should fire once")
    let seen: String val = String.from_array(_body = recover iso Array[U8] end)
    _h.assert_eq[String]("Hello, Body!\n", seen, "body did not match")
    _h.complete(true)

  fun ref on_body_chunk(data: Array[U8] val) =>
    _body.append(data)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _completes = _completes + 1
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureNoBodyActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  let _request: String val
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _completes: USize = 0
  var _body_chunks: USize = 0

  new create(h: TestHelper, fd: U32, request: String val) =>
    _h = h
    _request = request
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
    _http._on_received(recover iso Array[U8] .> append(_request) end)

    _h.assert_eq[USize](1, _completes, "on_request_complete should fire once")
    _h.assert_eq[USize](0, _body_chunks, "on_body_chunk should not fire")
    _h.complete(true)

  fun ref on_body_chunk(data: Array[U8] val) =>
    _body_chunks = _body_chunks + 1

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _completes = _completes + 1
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .build()
    responder.respond(response)

actor \nodoc\ _TestPurePipelinedBodiesActor is
  HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _current_body: Array[U8] iso = recover iso Array[U8] end
  embed _bodies: Array[String val]

  new create(h: TestHelper, fd: U32) =>
    _h = h
    _bodies = Array[String val]
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
      "POST /1 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\n" +
        "first" +
        "POST /2 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 6\r\n" +
        "Connection: close\r\n\r\nsecond"
    _http._on_received(recover iso Array[U8] .> append(requests) end)

    _h.assert_eq[USize](2, _bodies.size(), "expected two request bodies")
    try
      _h.assert_eq[String]("first", _bodies(0)?, "first body mismatch")
      _h.assert_eq[String]("second", _bodies(1)?, "second body mismatch")
    end
    _h.complete(true)

  fun ref on_body_chunk(data: Array[U8] val) =>
    _current_body.append(data)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let body: Array[U8] val =
      _current_body = recover iso Array[U8] end
    _bodies.push(String.from_array(body))
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .build()
    responder.respond(response)

actor \nodoc\ _TestPureCookieParsingActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()
  var _seen_session: String val = ""
  var _seen_theme: String val = ""

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
      "GET / HTTP/1.1\r\nHost: localhost\r\n" +
        "Cookie: session=abc123; theme=dark\r\n\r\n"
    _http._on_received(recover iso Array[U8] .> append(request) end)

    _h.assert_eq[String]("abc123", _seen_session, "session cookie mismatch")
    _h.assert_eq[String]("dark", _seen_theme, "theme cookie mismatch")
    _h.complete(true)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _seen_session =
      match request'.cookies.get("session")
      | let s: String val => s
      else ""
      end
    _seen_theme =
      match request'.cookies.get("theme")
      | let s: String val => s
      else ""
      end
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .build()
    responder.respond(response)
