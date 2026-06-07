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

// ---------------------------------------------------------------------------
// Host value vs. request-target authority cross-check (RFC 9110 §7.2) and the
// CONNECT-port requirement (RFC 9112 §3.2 / RFC 9110 §9.3.6). When the target
// carries its own authority (absolute-form or CONNECT) it must name the same
// host as the Host header; a disagreement is a routing-confusion / smuggling
// vector and is rejected with 400. Default-port normalization keeps benign
// absolute-form requests (e.g. Host without the implied :80) working.
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestServerAbsoluteFormHostMatch is UnitTest
  """Absolute-form target whose authority matches Host → 200."""
  fun name(): String => "server/absolute form host match"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45930"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormHostMismatch is UnitTest
  """Absolute-form target whose authority disagrees with Host → 400."""
  fun name(): String => "server/absolute form host mismatch"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45931"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://a.example/ HTTP/1.1\r\nHost: b.example\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormDefaultPort is UnitTest
  """Absolute-form `:80` vs portless Host is equivalent for http → 200."""
  fun name(): String => "server/absolute form default port"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45932"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://example.com:80/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormDefaultPortHTTPS is UnitTest
  """Absolute-form `:443` vs portless Host is equivalent for https → 200."""
  fun name(): String => "server/absolute form default port https"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45938"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET https://example.com:443/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormHostCaseInsensitive is UnitTest
  """Absolute-form host comparison with Host is case-insensitive → 200."""
  fun name(): String => "server/absolute form host case insensitive"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45933"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://EXAMPLE.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormPortMatch is UnitTest
  """Absolute-form non-default port agreeing with Host → 200."""
  fun name(): String => "server/absolute form port match"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45939"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://example.com:8080/ HTTP/1.1\r\nHost: example.com:8080\r\n\r\n",
          "200 OK", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormPortMismatch is UnitTest
  """Absolute-form whose port disagrees with Host (hosts agree) → 400."""
  fun name(): String => "server/absolute form port mismatch"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45940"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://example.com:8080/ HTTP/1.1\r\nHost: example.com:9090\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerConnectHostMismatch is UnitTest
  """CONNECT target authority disagreeing with Host → 400."""
  fun name(): String => "server/connect host mismatch"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45934"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "CONNECT a.example:443 HTTP/1.1\r\nHost: b.example:443\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormUserinfo is UnitTest
  """Absolute-form target carrying userinfo → 400 (RFC 9110 §4.2.4)."""
  fun name(): String => "server/absolute form userinfo"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45941"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://user@example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormMultipleAt is UnitTest
  """Absolute-form target with multiple `@` (userinfo) → 400 (RFC 9110 §4.2.4)."""
  fun name(): String => "server/absolute form multiple at"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45942"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://a@b@example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormUserinfoNoHost is UnitTest
  """
  HTTP/1.0 absolute-form target with userinfo and no Host → 400. Pins that the
  userinfo rejection runs independent of the Host header.
  """
  fun name(): String => "server/absolute form userinfo no host"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45943"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http://user@example.com/ HTTP/1.0\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerConnectUserinfo is UnitTest
  """CONNECT target carrying userinfo → 400 (RFC 9112 §3.2.3)."""
  fun name(): String => "server/connect userinfo"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45944"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "CONNECT user@example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerAbsoluteFormEmptyHost is UnitTest
  """Absolute-form target with an empty authority host → 400."""
  fun name(): String => "server/absolute form empty host"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45935"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "GET http:/// HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerConnectMissingPort is UnitTest
  """CONNECT target without a port → 400 (RFC 9112 §3.2)."""
  fun name(): String => "server/connect missing port"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45936"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "CONNECT example.com HTTP/1.1\r\nHost: example.com\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerConnectEmptyPort is UnitTest
  """CONNECT target with an empty port → 400 (RFC 9112 §3.2)."""
  fun name(): String => "server/connect empty port"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45937"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port',
          "CONNECT example.com: HTTP/1.1\r\nHost: example.com:\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)
