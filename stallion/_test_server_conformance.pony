use "pony_test"
use lori = "lori"

// ---------------------------------------------------------------------------
// HTTPServer-level (protocol-layer) conformance (Discussion #123 boundary).
//
// Request-target structure and Host presence/uniqueness live at the protocol
// layer, where URI and CONNECT handling already are — not in the parser. These
// drive a real connection through HTTPServer and assert on the status line,
// reusing the harness actors (_TestServerListener, _TestHelloServerFactory,
// _TestHTTPClient) defined in _test_server.pony.
//
// missing_host / duplicate_host encode NEW behavior (RFC 9110 §7.2 /
// 9112 §3.2): a server MUST answer 400 to an HTTP/1.1 request that lacks Host
// or carries more than one. Not enforced today — these are catalogue entries
// until the rewrite adds the check. connect_ok is a guard: a valid CONNECT
// (authority-form target + Host) is accepted.
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestServerMissingHost is UnitTest
  """HTTP/1.1 request with no Host header → 400 Bad Request (RFC 9110 §7.2)."""
  fun name(): String => "server/missing host"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45920"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.1\r\n\r\n", "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerDuplicateHost is UnitTest
  """HTTP/1.1 request with two Host headers → 400 Bad Request (RFC 9110 §7.2)."""
  fun name(): String => "server/duplicate host"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45921"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerConnectOk is UnitTest
  """A valid CONNECT (authority-form target + Host) is accepted."""
  fun name(): String => "server/connect ok"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45922"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerDuplicateHostWithBody is UnitTest
  """
  A duplicate-Host request that also carries a body → 400, and the body must not
  be processed: request_received rejects, stopping the parser before any body
  state. Exercises the `failed()` guard in the parser's _finish.
  """
  fun name(): String => "server/duplicate host with body"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45925"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "POST / HTTP/1.1\r\nHost: a\r\nHost: b\r\nContent-Length: 3\r\n\r\nabc",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerDuplicateHostHTTP10 is UnitTest
  """
  An HTTP/1.0 request with two Host headers → 400 (duplicate Host is rejected on
  any version, not just HTTP/1.1).
  """
  fun name(): String => "server/duplicate host http10"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45924"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerInvalidHostValue is UnitTest
  """
  An HTTP/1.1 request whose Host value is not a well-formed host → 400. `a, b`
  is one field line (so the uniqueness check passes), but the space makes it an
  invalid uri-host (RFC 9110 §7.2 / RFC 9112 §3.2).
  """
  fun name(): String => "server/invalid host value"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45926"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.1\r\nHost: a, b\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerHostPortOutOfRange is UnitTest
  """
  An HTTP/1.1 request whose Host port exceeds 65535 → 400. Pins the port range
  check end-to-end (this gate is the only place the Host header's port is
  validated).
  """
  fun name(): String => "server/host port out of range"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45929"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.1\r\nHost: example.com:99999\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerEmptyHostValue is UnitTest
  """
  An HTTP/1.1 request with a present-but-empty Host value is accepted: an empty
  reg-name is valid grammar, so the value gate does not reject it (pins the
  accept-empty decision).
  """
  fun name(): String => "server/empty host value"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45927"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.1\r\nHost:\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerIPv6HostValue is UnitTest
  """An IPv6-literal Host value (`[::1]`) is accepted."""
  fun name(): String => "server/ipv6 host value"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45928"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerUnknownMethod is UnitTest
  """A valid-token but unimplemented method → 501 Not Implemented."""
  fun name(): String => "server/unknown method"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45923"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "FOOBAR / HTTP/1.1\r\nHost: localhost\r\n\r\n",
          "501 Not Implemented", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)
