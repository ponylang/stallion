use "constrained_types"
use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"

class \nodoc\ iso _TestServerHelloWorld is UnitTest
  """
  Start a listener, connect a client, send a GET request,
  verify the server responds with 200 OK and "Hello, World!" body.
  """
  fun name(): String => "server/hello world"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45871"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
          "Hello, World!")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestKeepAlive is UnitTest
  """
  Send two HTTP/1.1 requests on the same connection. Verify both get
  200 OK responses (connection stays open between requests).
  """
  fun name(): String => "server/keep-alive"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45873"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestKeepAliveClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestIdleTimeout is UnitTest
  """
  Configure a 1-second idle timeout. Send one request,
  receive the response,
  then wait. Verify the connection closes within the test timeout.
  """
  fun name(): String => "server/idle timeout"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45879"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let idle_timeout =
      match lori.MakeIdleTimeout(1_000)
      | let t: lori.IdleTimeout => t
    end
    let config = ServerConfig(host, port where idle_timeout' = idle_timeout)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClientExpectClose(h', port', request, "200 OK")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestIdleTimeoutClosesStalledConnection is UnitTest
  """
  A connection that stalls mid-request must be closed by the idle timeout.

  Configure a 1-second idle timeout and a server whose handler never
  responds. The client sends a complete request and then does nothing, so
  the request is in flight with no socket activity. The idle timeout must
  still close the connection — completion is gated on the client seeing the
  close. Before the fix the idle timeout only fired between requests, so a
  connection stalled mid-request like this leaked.
  """
  fun name(): String => "server/idle timeout closes stalled connection"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45896"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let idle_timeout =
      match lori.MakeIdleTimeout(1_000)
      | let t: lori.IdleTimeout => t
    end
    let config = ServerConfig(host, port where idle_timeout' = idle_timeout)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestNeverRespondsServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestExpectIdleClose(h', port', request)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestNeverRespondsServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestNeverRespondsServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestNeverRespondsServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    // Never respond — the connection stalls mid-request. The idle timeout
    // must close it.
    None

actor \nodoc\ _TestExpectIdleClose is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val

  new create(h: TestHelper, port: String, request: String val) =>
    _h = h
    _request = request
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    // The server never produces a response; ignore anything that arrives.
    lori.KeepReading

  fun ref _on_closed() =>
    // The idle timeout closed the stalled connection — the fix works.
    _h.complete(true)

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("client connection failed")
    _h.complete(false)

