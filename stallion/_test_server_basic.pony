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

class \nodoc\ iso _TestServerParseError is UnitTest
  """
  Start a listener,
  connect a client,
  send garbage bytes,
  verify the connection responds with 400 Bad Request.
  """
  fun name(): String => "server/parse error"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45872"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestHTTPClient(
          h',
          port',
          "GARBAGE DATA\r\n\r\n",
          "400 Bad Request",
          None)
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

class \nodoc\ iso _TestConnectionClose is UnitTest
  """
  Send an HTTP/1.1 request with Connection: close. Verify the response
  arrives and the connection closes.
  """
  fun name(): String => "server/connection close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45874"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client = _TestHTTPClientExpectClose(h', port', request, "200 OK")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestHTTP10Close is UnitTest
  """
  Send an HTTP/1.0 request without Connection: keep-alive. Verify the
  response arrives and the connection closes.
  """
  fun name(): String => "server/http 1.0 close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45875"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClientExpectClose(h', port', request, "200 OK")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestErrorResponse413 is UnitTest
  """
  Configure a small max_body_size. Send a request with Content-Length
  exceeding the limit. Verify 413 Payload Too Large response.
  """
  fun name(): String => "server/error 413"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45876"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port where max_body_size' = 10)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "413 Payload Too Large",
          None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestErrorResponse431 is UnitTest
  """
  Configure a small max_header_size. Send a request with headers exceeding
  the limit. Verify 431 Request Header Fields Too Large response.
  """
  fun name(): String => "server/error 431"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45877"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port where max_header_size' = 10)
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
          "431 Request Header Fields Too Large",
          None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestErrorResponse505 is UnitTest
  """
  Send a request with HTTP/2.0 version. Verify 505 HTTP Version Not
  Supported response.
  """
  fun name(): String => "server/error 505"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45878"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/2.0\r\nHost: localhost\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "505 HTTP Version Not Supported",
          None)
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

class \nodoc\ iso _TestMaxRequestsPerConnection is UnitTest
  """
  Configure `max_requests_per_connection' = 2`. Send 3 pipelined HTTP/1.1
  requests. Verify exactly 2 responses arrive, then the connection closes.
  """
  fun name(): String => "server/max requests per connection"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45895"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let max_req =
      match \exhaustive\ MakeMaxRequestsPerConnection(2)
      | let m: MaxRequestsPerConnection => m
      | let _: ValidationFailure =>
      h.fail("Failed to create MaxRequestsPerConnection")
      h.complete(false)
      return
    end
    let config =
      ServerConfig(
      host, port where
      max_requests_per_connection' = max_req)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestMaxRequestsClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

actor \nodoc\ _TestMaxRequestsClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Send 3 pipelined requests in one buffer
    _tcp_connection.send(
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    lori.KeepReading

  fun ref _on_closed() =>
    let r: String val = _response.clone()
    // First "Hello, World!" must be present
    try
      r.find("Hello, World!")?
    else
      _h.fail("Expected at least one response")
      _h.complete(false)
      return
    end
    // Second "Hello, World!" must be present (nth=1)
    try
      r.find("Hello, World!", 0, 1)?
    else
      _h.fail("Expected two responses but only found one")
      _h.complete(false)
      return
    end
    // Third "Hello, World!" must NOT be present (nth=2)
    try
      r.find("Hello, World!", 0, 2)?
      _h.fail("Expected only two responses but found three")
      _h.complete(false)
    else
      // Good — third response absent means max-requests limit worked
      _h.complete(true)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

