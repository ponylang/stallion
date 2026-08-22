use "pony_test"
use lori = "lori"

// HTTPServer-level conformance covered by feeding a crafted request through
// `HTTPServer._on_received` and asserting on the captured status line.

class \nodoc\ iso _TestPureMissingHost is UnitTest
  """HTTP/1.1 request with no Host header → 400 Bad Request (RFC 9110 §7.2)."""
  fun name(): String => "pure/missing host"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.1\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureDuplicateHost is UnitTest
  """
  HTTP/1.1 request with two Host headers is 400 Bad Request
  (RFC 9110 §7.2).
  """
  fun name(): String => "pure/duplicate host"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureDuplicateHostHTTP10 is UnitTest
  """
  An HTTP/1.0 request with two Host headers → 400 (duplicate Host is rejected
  on any version, not just HTTP/1.1).
  """
  fun name(): String => "pure/duplicate host http10"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureDuplicateHostWithBody is UnitTest
  """
  A duplicate-Host request that also carries a body → 400, and the body must
  not be processed: `request_received` rejects, stopping the parser before any
  body state.
  """
  fun name(): String => "pure/duplicate host with body"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "POST / HTTP/1.1\r\nHost: a\r\nHost: b\r\n" +
        "Content-Length: 3\r\n\r\nabc",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureInvalidHostValue is UnitTest
  """
  An HTTP/1.1 request whose Host value is not a well-formed host → 400.
  `a, b` is one field line, but the space makes it an invalid uri-host.
  """
  fun name(): String => "pure/invalid host value"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.1\r\nHost: a, b\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureHostPortOutOfRange is UnitTest
  """An HTTP/1.1 request whose Host port exceeds 65535 → 400."""
  fun name(): String => "pure/host port out of range"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.1\r\nHost: example.com:99999\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureEmptyHostValue is UnitTest
  """
  A present-but-empty Host value is accepted: empty reg-name is valid
  grammar, so the value gate does not reject it.
  """
  fun name(): String => "pure/empty host value"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.1\r\nHost:\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureIPv6HostValue is UnitTest
  """An IPv6-literal Host value (`[::1]`) is accepted."""
  fun name(): String => "pure/ipv6 host value"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureConnectOk is UnitTest
  """A valid CONNECT (authority-form target + Host) is accepted."""
  fun name(): String => "pure/connect ok"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureUnknownMethod is UnitTest
  """A valid-token but unimplemented method → 501 Not Implemented."""
  fun name(): String => "pure/unknown method"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "FOOBAR / HTTP/1.1\r\nHost: localhost\r\n\r\n",
      "HTTP/1.1 501 Not Implemented")

class \nodoc\ iso _TestPureAbsoluteFormHostMatch is UnitTest
  """Absolute-form target whose authority matches Host → 200."""
  fun name(): String => "pure/absolute form host match"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureAbsoluteFormHostMismatch is UnitTest
  """Absolute-form target whose authority disagrees with Host → 400."""
  fun name(): String => "pure/absolute form host mismatch"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://a.example/ HTTP/1.1\r\nHost: b.example\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureAbsoluteFormDefaultPort is UnitTest
  """Absolute-form `:80` vs portless Host is equivalent for http → 200."""
  fun name(): String => "pure/absolute form default port"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://example.com:80/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureAbsoluteFormDefaultPortHTTPS is UnitTest
  """Absolute-form `:443` vs portless Host is equivalent for https → 200."""
  fun name(): String => "pure/absolute form default port https"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET https://example.com:443/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureAbsoluteFormHostCaseInsensitive is UnitTest
  """Absolute-form host comparison with Host is case-insensitive → 200."""
  fun name(): String => "pure/absolute form host case insensitive"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://EXAMPLE.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureAbsoluteFormPortMatch is UnitTest
  """Absolute-form non-default port agreeing with Host → 200."""
  fun name(): String => "pure/absolute form port match"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://example.com:8080/ HTTP/1.1\r\n" +
        "Host: example.com:8080\r\n\r\n",
      "HTTP/1.1 200 OK")

class \nodoc\ iso _TestPureAbsoluteFormPortMismatch is UnitTest
  """Absolute-form whose port disagrees with Host (hosts agree) → 400."""
  fun name(): String => "pure/absolute form port mismatch"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://example.com:8080/ HTTP/1.1\r\n" +
        "Host: example.com:9090\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureConnectHostMismatch is UnitTest
  """CONNECT target authority disagreeing with Host → 400."""
  fun name(): String => "pure/connect host mismatch"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "CONNECT a.example:443 HTTP/1.1\r\nHost: b.example:443\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureAbsoluteFormUserinfo is UnitTest
  """Absolute-form target carrying userinfo → 400 (RFC 9110 §4.2.4)."""
  fun name(): String => "pure/absolute form userinfo"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://user@example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureAbsoluteFormMultipleAt is UnitTest
  """
  Absolute-form target with multiple `@` (userinfo) is 400
  (RFC 9110 §4.2.4).
  """
  fun name(): String => "pure/absolute form multiple at"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://a@b@example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureAbsoluteFormUserinfoNoHost is UnitTest
  """
  HTTP/1.0 absolute-form target with userinfo and no Host → 400. Pins that
  the userinfo rejection runs independent of the Host header.
  """
  fun name(): String => "pure/absolute form userinfo no host"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http://user@example.com/ HTTP/1.0\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureConnectUserinfo is UnitTest
  """CONNECT target carrying userinfo → 400 (RFC 9112 §3.2.3)."""
  fun name(): String => "pure/connect userinfo"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "CONNECT user@example.com:443 HTTP/1.1\r\n" +
        "Host: example.com:443\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureAbsoluteFormEmptyHost is UnitTest
  """Absolute-form target with an empty authority host → 400."""
  fun name(): String => "pure/absolute form empty host"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "GET http:/// HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureConnectMissingPort is UnitTest
  """CONNECT target without a port → 400 (RFC 9112 §3.2)."""
  fun name(): String => "pure/connect missing port"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "CONNECT example.com HTTP/1.1\r\nHost: example.com\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

class \nodoc\ iso _TestPureConnectEmptyPort is UnitTest
  """CONNECT target with an empty port → 400 (RFC 9112 §3.2)."""
  fun name(): String => "pure/connect empty port"

  fun apply(h: TestHelper) =>
    _RunPureConformance(
      h,
      "CONNECT example.com: HTTP/1.1\r\nHost: example.com:\r\n\r\n",
      "HTTP/1.1 400 Bad Request")

primitive \nodoc\ _RunPureConformance
  """
  Spawn a `_TestPureConformanceActor` bound to `h` with the given request and
  expected status-line prefix. The actor allocates its own raw socket fd,
  runs the request through `HTTPServer[_TestFakeBackend]`, and completes the
  test after asserting on the captured wire bytes.
  """
  fun apply(h: TestHelper, request: String val, expected_status: String val) =>
    h.long_test(2_000_000_000)
    try
      let fd = _FakeServerFd()?
      let actor' = _TestPureConformanceActor(h, fd, request, expected_status)
      h.dispose_when_done(actor')
    else
      h.fail("could not allocate raw socket fd")
      h.complete(false)
    end

actor \nodoc\ _TestPureConformanceActor is HTTPServerActor[_TestFakeBackend]
  let _h: TestHelper
  let _request: String val
  let _expected: String val
  let _capture: _TestSendCapture = _TestSendCapture
  var _http: HTTPServer[_TestFakeBackend] =
    HTTPServer[_TestFakeBackend].none()

  new create(
    h: TestHelper,
    fd: U32,
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
        ServerConfig("localhost", "0"))
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
    // Minimal 200 OK. Only fires for accepted requests; rejected requests
    // get their error response from HTTPServer before this callback is
    // reached.
    let body: String val = ""
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", "0")
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
