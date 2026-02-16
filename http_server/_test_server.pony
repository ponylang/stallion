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
  fun apply(responder: Responder): Handler ref^ =>
    _TestHelloHandler(responder)

class \nodoc\ ref _TestHelloHandler is Handler
  let _responder: Responder

  new ref create(responder: Responder) =>
    _responder = responder

  fun ref request_complete() =>
    let headers = recover val
      let h = Headers
      h.set("content-type", "text/plain")
      h.set("content-length", "13")
      h
    end
    _responder.respond(StatusOK, headers, "Hello, World!")

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
