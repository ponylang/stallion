use "pony_test"
use lori = "lori"

class \nodoc\ iso _TestServerHelloWorld is UnitTest
  """
  Start a listener, connect a client, send a GET request,
  verify the handler responds with 200 OK and "Hello, World!" body.
  """
  fun name(): String => "server/hello world"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45871"
    let listener = _TestServerListener(h, port, _TestHelloFactory)
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
    let listener = _TestServerListener(h, port, _TestHelloFactory)
    h.dispose_when_done(listener)

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
  let _h: TestHelper
  let _port: String

  new create(h: TestHelper, port: String, handler_factory: HandlerFactory) =>
    _h = h
    _port = port
    _handler_factory = handler_factory
    let listen_auth = lori.TCPListenAuth(_h.env.root)
    _server_auth = lori.TCPServerAuth(listen_auth)
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_listener = lori.TCPListener(listen_auth, host, port, this)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _Connection =>
    _Connection(_server_auth, fd, _handler_factory)

  fun ref _on_listening() =>
    // Server is ready — start the test client based on which test is running
    if _port == "45871" then
      // Hello world test: send valid HTTP request
      let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
      let client = _TestHTTPClient(_h, _port, request, "200 OK",
        "Hello, World!")
      _h.dispose_when_done(client)
    elseif _port == "45872" then
      // Parse error test: send garbage
      let client = _TestHTTPClient(_h, _port, "GARBAGE DATA\r\n\r\n",
        "400 Bad Request", None)
      _h.dispose_when_done(client)
    end

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
