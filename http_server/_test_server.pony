use "pony_check"
use "pony_test"
use "time"
use lori = "lori"

// ---------------------------------------------------------------------------
// Existing tests (updated for new _Connection constructor)
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestServerHelloWorld is UnitTest
  """
  Start a listener, connect a client, send a GET request,
  verify the handler responds with 200 OK and "Hello, World!" body.
  """
  fun name(): String => "server/hello world"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45871"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
      {(h': TestHelper, port': String) =>
        let client = _TestHTTPClient(h', port', "GARBAGE DATA\r\n\r\n",
          "400 Bad Request", None)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// New integration tests
// ---------------------------------------------------------------------------

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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
    let config = ServerConfig(host, port where idle_timeout' = 1)
    let timers = Timers
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClientExpectClose(h', port', request, "200 OK")
        h'.dispose_when_done(client)
      }, timers)
    h.dispose_when_done(timers)
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerNotifyListening is UnitTest
  """
  Create a Server with a ServerNotify. Verify that the listening()
  callback fires.
  """
  fun name(): String => "server/notify listening"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let auth = lori.TCPListenAuth(h.env.root)
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, "45881")
    let notify = _TestListenNotify(h)
    let server = Server(auth, _TestHelloFactory, config, notify)
    h.dispose_when_done(server)

// ---------------------------------------------------------------------------
// Property-based test: keep-alive decision
// ---------------------------------------------------------------------------

class \nodoc\ iso _PropertyKeepAliveDecision
  is Property1[(Version, (String val | None))]
  """
  The keep-alive decision matches the HTTP/1.x spec:
  - HTTP/1.1 + no header → keep-alive
  - HTTP/1.1 + Connection: close (any case) → close
  - HTTP/1.0 + no header → close
  - HTTP/1.0 + Connection: keep-alive (any case) → keep-alive
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
// Test handler: responds with "Hello, World!" on every request
// ---------------------------------------------------------------------------

class \nodoc\ val _TestHelloFactory is HandlerFactory
  fun apply(): Handler ref^ =>
    _TestHelloHandler

class \nodoc\ ref _TestHelloHandler is Handler
  fun ref request_complete(responder: Responder) =>
    let headers = recover val
      let h = Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.respond(StatusOK, headers, "Hello, World!")

// ---------------------------------------------------------------------------
// Test listener: creates _Connection actors, starts test client
// ---------------------------------------------------------------------------

actor \nodoc\ _TestServerListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _handler_factory: HandlerFactory
  let _config: ServerConfig
  let _timers: (Timers | None)
  let _h: TestHelper
  let _port: String
  let _start_client: {(TestHelper, String)} val

  new create(
    h: TestHelper,
    port: String,
    handler_factory: HandlerFactory,
    config: ServerConfig,
    start_client: {(TestHelper, String)} val,
    timers: (Timers | None) = None)
  =>
    _h = h
    _port = port
    _handler_factory = handler_factory
    _config = config
    _timers = timers
    _start_client = start_client
    let listen_auth = lori.TCPListenAuth(_h.env.root)
    _server_auth = lori.TCPServerAuth(listen_auth)
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_listener = lori.TCPListener(listen_auth, host, port, this)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _Connection =>
    _Connection(_server_auth, fd, _handler_factory, _config, _timers)

  fun ref _on_listening() =>
    _start_client(_h, _port)

  fun ref _on_listen_failure() =>
    _h.fail("Listener failed to start on port " + _port)
    _h.complete(false)

// ---------------------------------------------------------------------------
// Test server notify: completes test on listening
// ---------------------------------------------------------------------------

class \nodoc\ val _TestListenNotify is ServerNotify
  let _h: TestHelper
  new val create(h: TestHelper) => _h = h
  fun listening(server: Server tag) => _h.complete(true)

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
  Send 3 GET requests in one buffer. Handler accumulates responders and
  responds in reverse order (2, 1, 0). Client verifies responses arrive
  in registration order (0, 1, 2).
  """
  fun name(): String => "server/pipeline correctness"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45882"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestPipelineFactory, config,
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
    let listener = _TestServerListener(h, port, _TestHelloFactory, config,
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
  Handler uses chunked transfer encoding to stream a response. Client
  verifies the response has Transfer-Encoding: chunked and contains
  all chunks.
  """
  fun name(): String => "server/streaming response"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45884"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener = _TestServerListener(h, port, _TestStreamFactory, config,
      {(h': TestHelper, port': String) =>
        let client = _TestStreamClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestMaxPendingOverflow is UnitTest
  """
  Configure max_pending_responses to 2. Use a handler that responds to the
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
      _TestPartialRespondFactory, config,
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
  Send an HTTP/1.0 request to a handler that attempts chunked encoding
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
      _TestChunkedFallbackFactory, config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n"
        let client = _TestHTTPClient(h', port', request, "200 OK",
          "fallback")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

// ---------------------------------------------------------------------------
// Pipeline test handler: accumulates responders, responds in reverse order
// ---------------------------------------------------------------------------

class \nodoc\ val _TestPipelineFactory is HandlerFactory
  fun apply(): Handler ref^ =>
    _TestPipelineHandler

class \nodoc\ ref _TestPipelineHandler is Handler
  embed _responders: Array[Responder]

  new ref create() =>
    _responders = Array[Responder]

  fun ref request_complete(responder: Responder) =>
    _responders.push(responder)
    if _responders.size() == 3 then
      // Respond in reverse order (2, 1, 0)
      // Queue ensures delivery in registration order (0, 1, 2)
      let headers = recover val
        let h = Headers
        h.set("content-type", "text/plain")
        h
      end
      try
        _responders(2)?.respond(StatusOK, headers, "response-2")
        _responders(1)?.respond(StatusOK, headers, "response-1")
        _responders(0)?.respond(StatusOK, headers, "response-0")
      end
    end

// ---------------------------------------------------------------------------
// Streaming test handler: sends chunked response
// ---------------------------------------------------------------------------

class \nodoc\ val _TestStreamFactory is HandlerFactory
  fun apply(): Handler ref^ =>
    _TestStreamHandler

class \nodoc\ ref _TestStreamHandler is Handler
  fun ref request_complete(responder: Responder) =>
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
// Partial-respond handler: responds to 1st request, holds rest — for overflow
// ---------------------------------------------------------------------------

class \nodoc\ val _TestPartialRespondFactory is HandlerFactory
  fun apply(): Handler ref^ =>
    _TestPartialRespondHandler

class \nodoc\ ref _TestPartialRespondHandler is Handler
  var _count: USize = 0

  fun ref request_complete(responder: Responder) =>
    _count = _count + 1
    if _count == 1 then
      let headers = recover val
        let h = Headers
        h.set("content-type", "text/plain")
        h
      end
      responder.respond(StatusOK, headers, "first-ok")
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
// Chunked fallback handler: tries chunked encoding, falls back to respond()
// ---------------------------------------------------------------------------

class \nodoc\ val _TestChunkedFallbackFactory is HandlerFactory
  fun apply(): Handler ref^ =>
    _TestChunkedFallbackHandler

class \nodoc\ ref _TestChunkedFallbackHandler is Handler
  fun ref request_complete(responder: Responder) =>
    let headers = recover val
      let h = Headers
      h.set("content-type", "text/plain")
      h
    end
    // Try chunked encoding — silently ignored for HTTP/1.0
    responder.start_chunked_response(StatusOK, headers)
    responder.send_chunk("chunk1")
    responder.finish_response()
    // Fallback: if chunked was rejected (HTTP/1.0), respond() still works
    // since the state is still _ResponderNotResponded
    responder.respond(StatusOK, headers, "fallback")
