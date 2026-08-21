use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"

interface \nodoc\ val _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor

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
    _http =
      match ssl_ctx
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

actor \nodoc\ _TestHTTPClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  let _expected_status: String val
  let _expected_body: (String val | None)
  var _response: String ref = String
  var _completed: Bool = false

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
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    // Check if we have a complete response (headers end with \r\n\r\n)
    if _response.contains("\r\n\r\n") then
      _verify_response()
    end
    lori.KeepReading

  fun ref _on_closed() =>
    // A close after the test's outcome is decided is not a failure.
    if not _completed then
      _h.fail("Connection closed before the response arrived:\n" + _response)
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

  fun ref _verify_response() =>
    _completed = true
    let response: String val = _response.clone()

    // Verify status line contains expected status
    if not response.contains(_expected_status) then
      _h.fail("Expected status '" + _expected_status +
        "' not found in response:\n" + response)
      _h.complete(false)
      return
    end

    // Verify body if expected
    match _expected_body
    | let body: String val =>
      if not response.contains(body) then
        _h.fail("Expected body '" + body +
          "' not found in response:\n" + response)
        _h.complete(false)
        return
      end
    end

    _h.complete(true)

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
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    if _response.contains("\r\n\r\n") then
      let response: String val = _response.clone()
      if response.contains(_expected_status) then
        _response_ok = true
      else
        _h.fail("Expected status '" + _expected_status +
          "' not found in response:\n" + response)
        _h.complete(false)
      end
    end
    lori.KeepReading

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

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

actor \nodoc\ _TestKeepAliveClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _requests_sent: USize = 0
  var _completed: Bool = false

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _requests_sent = 1
    _tcp_connection.send(
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
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
        _completed = true
        _h.complete(true)
      end
    end
    lori.KeepReading

  fun ref _on_closed() =>
    // A close after the test's outcome is decided is not a failure.
    if not _completed then
      _h.fail("Connection closed before both requests completed:\n" + _response)
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

