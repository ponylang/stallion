use "constrained_types"
use "files"
use "pony_check"
use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"
use uri = "uri"

// ---------------------------------------------------------------------------
// Server integration tests
// ---------------------------------------------------------------------------

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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "Hello, World!")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerParseError is UnitTest
  """
  Start a listener, connect a client, send garbage bytes,
  verify the connection responds with 400 Bad Request.
  """
  fun name(): String => "server/parse error"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45872"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port', "GARBAGE DATA\r\n\r\n",
          "400 Bad Request", None)
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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n"
        let client = _TestHTTPClient(h', port', request,
          "413 Payload Too Large", None)
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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request,
          "431 Request Header Fields Too Large", None)
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
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/2.0\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request,
          "505 HTTP Version Not Supported", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestIdleTimeout is UnitTest
  """
  Configure a 1-second idle timeout. Send one request, receive the response,
  then wait. Verify the connection closes within the test timeout.
  """
  fun name(): String => "server/idle timeout"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45879"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let idle_timeout = match lori.MakeIdleTimeout(1_000)
    | let t: lori.IdleTimeout => t
    end
    let config = ServerConfig(host, port where idle_timeout' = idle_timeout)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClientExpectClose(h', port', request, "200 OK")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

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
    let max_req = match MakeMaxRequestsPerConnection(2)
    | let m: MaxRequestsPerConnection => m
    | let _: ValidationFailure =>
      h.fail("Failed to create MaxRequestsPerConnection")
      h.complete(false)
      return
    end
    let config = ServerConfig(host, port where
      max_requests_per_connection' = max_req)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
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
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Send 3 pipelined requests in one buffer
    _tcp_connection.send(
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)

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

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Property-based test: keep-alive decision
// ---------------------------------------------------------------------------

class \nodoc\ iso _PropertyKeepAliveDecision
  is Property1[(Version, (String val | None))]
  """
  The keep-alive decision matches the HTTP/1.x spec:
  - HTTP/1.1 + no header -> keep-alive
  - HTTP/1.1 + Connection: close (any case) -> close
  - HTTP/1.0 + no header -> close
  - HTTP/1.0 + Connection: keep-alive (any case) -> keep-alive
  - Unrecognized Connection values use version default
  """
  fun name(): String => "keep-alive/decision"

  fun gen(): Generator[(Version, (String val | None))] =>
    let version_gen = Generators.one_of[Version](
      [as Version: HTTP10; HTTP11])

    let known_gen: Generator[(String val | None)] =
      Generators.one_of[(String val | None)](
        [as (String val | None):
          None; "close"; "Close"; "CLOSE"
          "keep-alive"; "Keep-Alive"; "KEEP-ALIVE"])

    let random_gen: Generator[(String val | None)] =
      Generators.ascii_printable(1, 20)
        .map[(String val | None)](
          {(s: String val): (String val | None) => s})

    let connection_gen = Generators.frequency[(String val | None)]([
      as WeightedGenerator[(String val | None)]:
      (5, known_gen)
      (2, random_gen)
    ])

    Generators.zip2[Version, (String val | None)](
      version_gen, connection_gen)

  fun ref property(
    arg1: (Version, (String val | None)),
    ph: PropertyHelper)
  =>
    (let version, let connection) = arg1
    let result = _KeepAliveDecision(version, connection)

    match connection
    | let c: String =>
      let lower = c.lower()
      if lower == "close" then
        ph.assert_false(result,
          "Connection: close should always close")
        return
      end
      if lower == "keep-alive" then
        ph.assert_true(result,
          "Connection: keep-alive should always keep alive")
        return
      end
    end

    // No header or unrecognized value: version-dependent
    if version is HTTP11 then
      ph.assert_true(result, "HTTP/1.1 default should be keep-alive")
    else
      ph.assert_false(result, "HTTP/1.0 default should be close")
    end

// ---------------------------------------------------------------------------
// Test-only connection factory interface
// ---------------------------------------------------------------------------

interface \nodoc\ val _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor

// ---------------------------------------------------------------------------
// Test server actor: responds with "Hello, World!" on every request
// ---------------------------------------------------------------------------

class \nodoc\ val _TestHelloServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestHelloServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestHelloServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let resp_body: String val = "Hello, World!"
    let response = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

// ---------------------------------------------------------------------------
// Test listener: creates server actors, starts test client
// ---------------------------------------------------------------------------

actor \nodoc\ _TestServerListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _connection_factory: _TestConnectionFactory
  let _config: ServerConfig
  let _ssl_ctx: (ssl_net.SSLContext val | None)
  let _h: TestHelper
  let _port: String
  let _start_client: {(TestHelper, String)} val

  new create(
    h: TestHelper,
    port: String,
    connection_factory: _TestConnectionFactory,
    config: ServerConfig,
    start_client: {(TestHelper, String)} val,
    ssl_ctx: (ssl_net.SSLContext val | None) = None)
  =>
    _h = h
    _port = port
    _connection_factory = connection_factory
    _config = config
    _ssl_ctx = ssl_ctx
    _start_client = start_client
    let listen_auth = lori.TCPListenAuth(_h.env.root)
    _server_auth = lori.TCPServerAuth(listen_auth)
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_listener = lori.TCPListener(listen_auth, host, port, this)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    _connection_factory(_server_auth, fd, _config, _ssl_ctx)

  fun ref _on_listening() =>
    _start_client(_h, _port)

  fun ref _on_listen_failure() =>
    _h.fail("Listener failed to start on port " + _port)
    _h.complete(false)

// ---------------------------------------------------------------------------
// Test client: sends request bytes, verifies response
// ---------------------------------------------------------------------------

actor \nodoc\ _TestHTTPClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  let _expected_status: String val
  let _expected_body: (String val | None)
  var _response: String ref = String

  new create(
    h: TestHelper,
    port: String,
    request: String val,
    expected_status: String val,
    expected_body: (String val | None))
  =>
    _h = h
    _request = request
    _expected_status = expected_status
    _expected_body = expected_body
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    // Check if we have a complete response (headers end with \r\n\r\n)
    if _response.contains("\r\n\r\n") then
      _verify_response()
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

  fun ref _verify_response() =>
    let response: String val = _response.clone()

    // Verify status line contains expected status
    if not response.contains(_expected_status) then
      _h.fail("Expected status '" + _expected_status
        + "' not found in response:\n" + response)
      _h.complete(false)
      return
    end

    // Verify body if expected
    match _expected_body
    | let body: String val =>
      if not response.contains(body) then
        _h.fail("Expected body '" + body
          + "' not found in response:\n" + response)
        _h.complete(false)
        return
      end
    end

    _h.complete(true)

// ---------------------------------------------------------------------------
// Test client: sends request, verifies response AND connection close
// ---------------------------------------------------------------------------

actor \nodoc\ _TestHTTPClientExpectClose is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  let _expected_status: String val
  var _response: String ref = String
  var _response_ok: Bool = false

  new create(
    h: TestHelper,
    port: String,
    request: String val,
    expected_status: String val)
  =>
    _h = h
    _request = request
    _expected_status = expected_status
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    if _response.contains("\r\n\r\n") then
      let response: String val = _response.clone()
      if response.contains(_expected_status) then
        _response_ok = true
      else
        _h.fail("Expected status '" + _expected_status
          + "' not found in response:\n" + response)
        _h.complete(false)
      end
    end

  fun ref _on_closed() =>
    if _response_ok then
      _h.complete(true)
    else
      // Response may not have been checked yet — check now
      let response: String val = _response.clone()
      if response.contains(_expected_status) then
        _h.complete(true)
      else
        _h.fail("Connection closed before valid response received")
        _h.complete(false)
      end
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Test client: sends two requests on same connection (keep-alive)
// ---------------------------------------------------------------------------

actor \nodoc\ _TestKeepAliveClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _requests_sent: USize = 0

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _requests_sent = 1
    _tcp_connection.send(
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()

    if _requests_sent == 1 then
      // Wait for first complete response
      try
        r.find("Hello, World!")?
        // First response received — send second request
        _requests_sent = 2
        _tcp_connection.send(
          "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n")
      end
    elseif _requests_sent == 2 then
      // Wait for second "Hello, World!" (the 2nd occurrence, 0-indexed nth)
      try
        r.find("Hello, World!", 0, 1)?
        _h.complete(true)
      end
    end

  fun ref _on_closed() =>
    if _requests_sent < 2 then
      _h.fail("Connection closed before both requests completed")
      _h.complete(false)
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Pipelining integration tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestPipelineCorrectness is UnitTest
  """
  Send 3 GET requests in one buffer. Server accumulates responders and
  responds in reverse order (2, 1, 0). Client verifies responses arrive
  in registration order (0, 1, 2).
  """
  fun name(): String => "server/pipeline correctness"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45882"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestPipelineServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestPipelineClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestPipelineConnectionClose is UnitTest
  """
  Send 2 pipelined requests, second has Connection: close. Verify both
  responses arrive, then the connection closes.
  """
  fun name(): String => "server/pipeline connection close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45883"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /2 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client = _TestPipelineCloseClient(h', port', request)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestStreamingResponse is UnitTest
  """
  Server uses chunked transfer encoding to stream a response. Client
  verifies the response has Transfer-Encoding: chunked and contains
  all chunks.
  """
  fun name(): String => "server/streaming response"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45884"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestStreamServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestStreamClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestMaxPendingOverflow is UnitTest
  """
  Configure max_pending_responses to 2. Use a server that responds to the
  first request but holds subsequent Responders. Send 4 pipelined requests.
  Verify:
  - The first request gets a 200 OK response (not overflow)
  - Eventually a 500 Internal Server Error arrives (overflow at request 4)
  - The connection closes
  """
  fun name(): String => "server/max pending overflow"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45885"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port where max_pending_responses' = 2)
    let listener = _TestServerListener(h, port,
      _TestPartialRespondServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /4 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestMaxPendingClient(h', port', request)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestHTTP10ChunkedRejection is UnitTest
  """
  Send an HTTP/1.0 request to a server that attempts chunked encoding
  then falls back to respond(). Verify that chunked is silently rejected
  (HTTP/1.0 doesn't support it) and the fallback respond() succeeds.
  """
  fun name(): String => "server/http 1.0 chunked rejection"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45886"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestChunkedFallbackServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "fallback")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// Pipeline test server: accumulates responders, responds in reverse order
// ---------------------------------------------------------------------------

class \nodoc\ val _TestPipelineServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestPipelineServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestPipelineServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  embed _responders: Array[Responder]

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _responders = Array[Responder]
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _responders.push(responder)
    if _responders.size() == 3 then
      // Respond in reverse order (2, 1, 0)
      // Queue ensures delivery in registration order (0, 1, 2)
      try
        _respond(_responders(2)?, "response-2")
        _respond(_responders(1)?, "response-1")
        _respond(_responders(0)?, "response-0")
      end
    end

  fun ref _respond(responder: Responder, resp_body: String val) =>
    let response = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

// ---------------------------------------------------------------------------
// Streaming test server: sends chunked response
// ---------------------------------------------------------------------------

class \nodoc\ val _TestStreamServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestStreamServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestStreamServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers = recover val
      let h = Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.start_chunked_response(StatusOK, headers)
    responder.send_chunk("chunk1")
    responder.send_chunk("chunk2")
    responder.send_chunk("chunk3")
    responder.finish_response()

// ---------------------------------------------------------------------------
// Pipeline client: sends 3 requests, verifies in-order responses
// ---------------------------------------------------------------------------

actor \nodoc\ _TestPipelineClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Send 3 pipelined requests in one buffer
    _tcp_connection.send(
      "GET /0 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Check if we have all 3 responses
    if r.contains("response-2") then
      try
        let pos0 = r.find("response-0")?
        let pos1 = r.find("response-1")?
        let pos2 = r.find("response-2")?
        if (pos0 < pos1) and (pos1 < pos2) then
          _h.complete(true)
        else
          _h.fail("Responses arrived out of order: pos0="
            + pos0.string() + " pos1=" + pos1.string()
            + " pos2=" + pos2.string())
          _h.complete(false)
        end
      else
        _h.fail("Could not find all response bodies in:\n" + r)
        _h.complete(false)
      end
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Pipeline close client: sends 2 requests, second with Connection: close
// ---------------------------------------------------------------------------

actor \nodoc\ _TestPipelineCloseClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  var _response: String ref = String
  var _got_responses: Bool = false

  new create(h: TestHelper, port: String, request: String val) =>
    _h = h
    _request = request
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Look for 2 occurrences of "Hello, World!"
    try
      r.find("Hello, World!", 0, 1)?  // Find 2nd occurrence (0-indexed nth)
      _got_responses = true
    end

  fun ref _on_closed() =>
    if _got_responses then
      _h.complete(true)
    else
      let r: String val = _response.clone()
      try
        r.find("Hello, World!", 0, 1)?
        _h.complete(true)
      else
        _h.fail(
          "Connection closed before both responses received:\n" + r)
        _h.complete(false)
      end
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Streaming client: sends request, verifies chunked response
// ---------------------------------------------------------------------------

actor \nodoc\ _TestStreamClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Check for terminal chunk
    if r.contains("0\r\n\r\n") then
      // Verify Transfer-Encoding: chunked header (case-insensitive check)
      if not (r.contains("Transfer-Encoding: chunked")
        or r.contains("transfer-encoding: chunked"))
      then
        _h.fail(
          "Missing Transfer-Encoding: chunked header in:\n" + r)
        _h.complete(false)
        return
      end
      // Verify chunk data is present
      if not (r.contains("chunk1") and r.contains("chunk2")
        and r.contains("chunk3"))
      then
        _h.fail("Missing chunk data in:\n" + r)
        _h.complete(false)
        return
      end
      _h.complete(true)
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Partial-respond server: responds to 1st request, holds rest — for overflow
// ---------------------------------------------------------------------------

class \nodoc\ val _TestPartialRespondServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestPartialRespondServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestPartialRespondServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  var _count: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _count = _count + 1
    if _count == 1 then
      let resp_body: String val = "first-ok"
      let response = ResponseBuilder(StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", resp_body.size().string())
        .finish_headers()
        .add_chunk(resp_body)
        .build()
      responder.respond(response)
    end
    // Subsequent requests: intentionally never respond

// ---------------------------------------------------------------------------
// Max pending client: verifies 200 before 500 overflow, then close
// ---------------------------------------------------------------------------

actor \nodoc\ _TestMaxPendingClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  var _response: String ref = String
  var _got_ok: Bool = false
  var _got_500: Bool = false

  new create(h: TestHelper, port: String, request: String val) =>
    _h = h
    _request = request
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    if (not _got_ok) and r.contains("first-ok") then
      _got_ok = true
    end
    if (not _got_500) and r.contains("500 Internal Server Error") then
      _got_500 = true
    end

  fun ref _on_closed() =>
    if _got_ok and _got_500 then
      _h.complete(true)
    elseif not _got_ok then
      _h.fail("Never received initial 200 OK before overflow")
      _h.complete(false)
    elseif not _got_500 then
      _h.fail("Never received 500 overflow response")
      _h.complete(false)
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// Chunked fallback server: tries chunked encoding, falls back to respond()
// ---------------------------------------------------------------------------

class \nodoc\ val _TestChunkedFallbackServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestChunkedFallbackServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestChunkedFallbackServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers = recover val
      let h = Headers
      h.set("content-type", "text/plain")
      h
    end
    match responder.start_chunked_response(StatusOK, headers)
    | StreamingStarted =>
      responder.send_chunk("chunk1")
      responder.finish_response()
    | ChunkedNotSupported =>
      let fallback_body: String val = "fallback"
      let response = ResponseBuilder(StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", fallback_body.size().string())
        .finish_headers()
        .add_chunk(fallback_body)
        .build()
      responder.respond(response)
    | AlreadyResponded => None
    end

class \nodoc\ iso _TestChunkSentCallback is UnitTest
  """
  Server uses `on_chunk_sent()` to drive subsequent chunks. Client sends a
  request, reads the complete chunked response, and verifies all chunks
  arrived. This exercises the full _on_sent -> HTTPServer -> actor chain.
  """
  fun name(): String => "server/on_chunk_sent callback"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45894"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestChunkSentServerFactory, config,
      {(h': TestHelper, port': String) =>
        let client = _TestChunkSentClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// on_chunk_sent test server: drives chunks from on_chunk_sent callback
// ---------------------------------------------------------------------------

class \nodoc\ val _TestChunkSentServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestChunkSentServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestChunkSentServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  var _responder: (Responder | None) = None
  var _chunks_sent: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers = recover val
      let h = Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.start_chunked_response(StatusOK, headers)
    responder.send_chunk("cs-chunk-1")
    _responder = responder
    _chunks_sent = 1

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    match _responder
    | let r: Responder =>
      _chunks_sent = _chunks_sent + 1
      if _chunks_sent <= 3 then
        r.send_chunk("cs-chunk-" + _chunks_sent.string())
      else
        r.finish_response()
        _responder = None
      end
    end

// ---------------------------------------------------------------------------
// on_chunk_sent client: sends request, verifies flow-controlled chunked response
// ---------------------------------------------------------------------------

actor \nodoc\ _TestChunkSentClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Check for terminal chunk
    if r.contains("0\r\n\r\n") then
      if not (r.contains("Transfer-Encoding: chunked")
        or r.contains("transfer-encoding: chunked"))
      then
        _h.fail(
          "Missing Transfer-Encoding: chunked header in:\n" + r)
        _h.complete(false)
        return
      end
      // Verify all 3 chunks arrived
      if not (r.contains("cs-chunk-1") and r.contains("cs-chunk-2")
        and r.contains("cs-chunk-3"))
      then
        _h.fail("Missing chunk data in:\n" + r)
        _h.complete(false)
        return
      end
      _h.complete(true)
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// URI parsing integration tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestURIParsing is UnitTest
  """
  Send a GET request with path and query string. Verify the server
  receives a pre-parsed URI with correct path and query components.
  """
  fun name(): String => "server/uri parsing"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45887"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestURIParsingServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET /hello?name=test HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "/hello|name=test")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestURIParsingServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestURIParsingServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestURIParsingServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let uri_query: String val = match request'.uri.query
    | let q: String val => q
    | None => ""
    end
    let resp_body: String val = request'.uri.path + "|" + uri_query
    let response = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

class \nodoc\ iso _TestConnectURIParsing is UnitTest
  """
  Send a CONNECT request with authority-form target. Verify the server
  receives a URI with the authority component populated and an empty path.
  """
  fun name(): String => "server/connect uri parsing"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45888"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestConnectURIServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request =
          "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "example.com|443|")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestConnectURIServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestConnectURIServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestConnectURIServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    var host: String val = ""
    var port: String val = ""
    match request'.uri.authority
    | let a: uri.URIAuthority val =>
      host = a.host
      port = match a.port
      | let p: U16 => p.string()
      | None => "none"
      end
    end
    let resp_body: String val = host + "|" + port + "|" + request'.uri.path
    let response = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

// ---------------------------------------------------------------------------
// Request body integration tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestBody is UnitTest
  """
  Send a POST with a body. Server accumulates body chunks and echoes
  the body in the response.
  """
  fun name(): String => "server/body"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45889"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestBodyServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "POST / HTTP/1.1\r\nHost: localhost\r\n" +
          "Content-Length: 13\r\n\r\nHello, Body!\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "Hello, Body!\n")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestBodyServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestBodyServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestBodyServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  var _body: Array[U8] iso = recover iso Array[U8] end
  var _has_body: Bool = false

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_body_chunk(data: Array[U8] val) =>
    _has_body = true
    _body.append(data)

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let resp_body: String val =
      if _has_body then
        _has_body = false
        let body: Array[U8] val = (_body = recover iso Array[U8] end)
        String.from_array(body)
      else
        "no body"
      end
    let response = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

class \nodoc\ iso _TestServerNoBody is UnitTest
  """
  Send a GET (no body). Verify that `on_request_complete` fires with
  no prior `on_body_chunk` calls.
  """
  fun name(): String => "server/no body"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45891"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestBodyServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "no body")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerContentLengthZero is UnitTest
  """
  Send a POST with Content-Length: 0. Verify that `on_request_complete` fires
  with no prior `on_body_chunk` calls (same as no body).
  """
  fun name(): String => "server/content-length zero"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45892"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestBodyServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "POST / HTTP/1.1\r\nHost: localhost\r\n" +
          "Content-Length: 0\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "no body")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestPipelinedBodies is UnitTest
  """
  Send two pipelined POSTs with different bodies. Verify each request
  gets its own body — the accumulator resets between requests.
  """
  fun name(): String => "server/pipelined bodies"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45893"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port,
      _TestBodyServerFactory, config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "POST /1 HTTP/1.1\r\nHost: localhost\r\n" +
          "Content-Length: 5\r\n\r\nfirst" +
          "POST /2 HTTP/1.1\r\nHost: localhost\r\n" +
          "Content-Length: 6\r\nConnection: close\r\n\r\nsecond"
        let client = _TestPipelinedBodiesClient(h', port', request)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// Pipelined bodies client: verifies each response has the correct body
// ---------------------------------------------------------------------------

actor \nodoc\ _TestPipelinedBodiesClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  var _response: String ref = String
  var _got_first: Bool = false
  var _got_second: Bool = false

  new create(h: TestHelper, port: String, request: String val) =>
    _h = h
    _request = request
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    if (not _got_first) and r.contains("first") then
      _got_first = true
    end
    if (not _got_second) and r.contains("second") then
      _got_second = true
    end

  fun ref _on_closed() =>
    if _got_first and _got_second then
      // Verify "first" appears before "second" (correct ordering)
      let r: String val = _response.clone()
      try
        let pos_first = r.find("first")?
        let pos_second = r.find("second")?
        if pos_first < pos_second then
          _h.complete(true)
        else
          _h.fail("Bodies arrived out of order")
          _h.complete(false)
        end
      else
        _h.fail("Could not find both bodies in response")
        _h.complete(false)
      end
    elseif not _got_first then
      _h.fail("Never received first body")
      _h.complete(false)
    else
      _h.fail("Never received second body")
      _h.complete(false)
    end

  fun ref _on_connection_failure() =>
    _h.fail("Client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// SSL integration tests
// ---------------------------------------------------------------------------

primitive \nodoc\ _TestSSLContext
  """
  Create an SSLContext val from the test certificates in assets/.

  Used by both server and client: SSLContext is val, so server() and client()
  create independent SSL sessions from the shared context.
  """
  fun apply(auth: AmbientAuth): ssl_net.SSLContext val ? =>
    let file_auth = FileAuth(auth)
    recover val
      ssl_net.SSLContext
        .> set_authority(
          FilePath(file_auth, "assets/cert.pem"))?
        .> set_cert(
          FilePath(file_auth, "assets/cert.pem"),
          FilePath(file_auth, "assets/key.pem"))?
        .> set_client_verify(false)
        .> set_server_verify(false)
    end

// ---------------------------------------------------------------------------
// SSL test: basic hello world over HTTPS
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestSSLHelloWorld is UnitTest
  """
  Start a listener with SSL, connect an SSL client, send a GET request,
  verify the server responds with 200 OK and "Hello, World!" body.
  Exercises the full SSL path: handshake -> request -> response.
  """
  fun name(): String => "server/ssl hello world"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let sslctx =
      try _TestSSLContext(h.env.root)?
      else
        h.fail("Unable to set up SSL context")
        h.complete(false)
        return
      end
    let port = "45900"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestSSLHTTPClient(h', sslctx, port', request, "200 OK",
          "Hello, World!")
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// SSL test: keep-alive (two requests on same SSL connection)
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestSSLKeepAlive is UnitTest
  """
  Send two HTTP/1.1 requests on the same SSL connection. Verify both get
  200 OK responses (SSL connection stays open between requests).
  """
  fun name(): String => "server/ssl keep-alive"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let sslctx =
      try _TestSSLContext(h.env.root)?
      else
        h.fail("Unable to set up SSL context")
        h.complete(false)
        return
      end
    let port = "45901"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestSSLKeepAliveClient(h', sslctx, port')
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// SSL test: connection close
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestSSLConnectionClose is UnitTest
  """
  Send an HTTP/1.1 request with Connection: close over SSL. Verify the
  response arrives and the connection closes.
  """
  fun name(): String => "server/ssl connection close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let sslctx =
      try _TestSSLContext(h.env.root)?
      else
        h.fail("Unable to set up SSL context")
        h.complete(false)
        return
      end
    let port = "45902"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client = _TestSSLHTTPClientExpectClose(h', sslctx, port', request,
          "200 OK")
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// SSL test: parse error (garbage bytes over SSL)
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestSSLParseError is UnitTest
  """
  Send garbage bytes over an SSL connection. Verify the server responds
  with 400 Bad Request over the encrypted connection.
  """
  fun name(): String => "server/ssl parse error"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let sslctx =
      try _TestSSLContext(h.env.root)?
      else
        h.fail("Unable to set up SSL context")
        h.complete(false)
        return
      end
    let port = "45903"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestSSLHTTPClient(h', sslctx, port',
          "GARBAGE DATA\r\n\r\n", "400 Bad Request", None)
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// SSL test: chunked streaming response
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestSSLStreamingResponse is UnitTest
  """
  Server uses chunked transfer encoding to stream a response over SSL.
  Client verifies the response has Transfer-Encoding: chunked and contains
  all chunks.
  """
  fun name(): String => "server/ssl streaming response"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let sslctx =
      try _TestSSLContext(h.env.root)?
      else
        h.fail("Unable to set up SSL context")
        h.complete(false)
        return
      end
    let port = "45904"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestStreamServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestSSLStreamClient(h', sslctx, port')
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// SSL test client: sends request, verifies response
// ---------------------------------------------------------------------------

actor \nodoc\ _TestSSLHTTPClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  let _expected_status: String val
  let _expected_body: (String val | None)
  var _response: String ref = String

  new create(
    h: TestHelper,
    ssl_ctx: ssl_net.SSLContext val,
    port: String,
    request: String val,
    expected_status: String val,
    expected_body: (String val | None))
  =>
    _h = h
    _request = request
    _expected_status = expected_status
    _expected_body = expected_body
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    if _response.contains("\r\n\r\n") then
      _verify_response()
    end

  fun ref _on_connection_failure() =>
    _h.fail("SSL client connection failed")
    _h.complete(false)

  fun ref _verify_response() =>
    let response: String val = _response.clone()

    if not response.contains(_expected_status) then
      _h.fail("Expected status '" + _expected_status
        + "' not found in response:\n" + response)
      _h.complete(false)
      return
    end

    match _expected_body
    | let body: String val =>
      if not response.contains(body) then
        _h.fail("Expected body '" + body
          + "' not found in response:\n" + response)
        _h.complete(false)
        return
      end
    end

    _h.complete(true)

// ---------------------------------------------------------------------------
// SSL test client: sends request, verifies response AND connection close
// ---------------------------------------------------------------------------

actor \nodoc\ _TestSSLHTTPClientExpectClose is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  let _expected_status: String val
  var _response: String ref = String
  var _response_ok: Bool = false

  new create(
    h: TestHelper,
    ssl_ctx: ssl_net.SSLContext val,
    port: String,
    request: String val,
    expected_status: String val)
  =>
    _h = h
    _request = request
    _expected_status = expected_status
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    if _response.contains("\r\n\r\n") then
      let response: String val = _response.clone()
      if response.contains(_expected_status) then
        _response_ok = true
      else
        _h.fail("Expected status '" + _expected_status
          + "' not found in response:\n" + response)
        _h.complete(false)
      end
    end

  fun ref _on_closed() =>
    if _response_ok then
      _h.complete(true)
    else
      let response: String val = _response.clone()
      if response.contains(_expected_status) then
        _h.complete(true)
      else
        _h.fail("Connection closed before valid response received")
        _h.complete(false)
      end
    end

  fun ref _on_connection_failure() =>
    _h.fail("SSL client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// SSL test client: sends two requests on same connection (keep-alive)
// ---------------------------------------------------------------------------

actor \nodoc\ _TestSSLKeepAliveClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _requests_sent: USize = 0

  new create(
    h: TestHelper,
    ssl_ctx: ssl_net.SSLContext val,
    port: String)
  =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _requests_sent = 1
    _tcp_connection.send(
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()

    if _requests_sent == 1 then
      try
        r.find("Hello, World!")?
        _requests_sent = 2
        _tcp_connection.send(
          "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n")
      end
    elseif _requests_sent == 2 then
      try
        r.find("Hello, World!", 0, 1)?
        _h.complete(true)
      end
    end

  fun ref _on_closed() =>
    if _requests_sent < 2 then
      _h.fail("Connection closed before both requests completed")
      _h.complete(false)
    end

  fun ref _on_connection_failure() =>
    _h.fail("SSL client connection failed")
    _h.complete(false)

// ---------------------------------------------------------------------------
// SSL test client: sends request, verifies chunked response
// ---------------------------------------------------------------------------

actor \nodoc\ _TestSSLStreamClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)

  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String

  new create(
    h: TestHelper,
    ssl_ctx: ssl_net.SSLContext val,
    port: String)
  =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso) =>
    _response.append(consume data)
    let r: String val = _response.clone()
    if r.contains("0\r\n\r\n") then
      if not (r.contains("Transfer-Encoding: chunked")
        or r.contains("transfer-encoding: chunked"))
      then
        _h.fail(
          "Missing Transfer-Encoding: chunked header in:\n" + r)
        _h.complete(false)
        return
      end
      if not (r.contains("chunk1") and r.contains("chunk2")
        and r.contains("chunk3"))
      then
        _h.fail("Missing chunk data in:\n" + r)
        _h.complete(false)
        return
      end
      _h.complete(true)
    end

  fun ref _on_connection_failure() =>
    _h.fail("SSL client connection failed")
    _h.complete(false)
