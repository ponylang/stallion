use "files"
use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"

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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client =
          _TestSSLHTTPClient(
          h',
          sslctx,
          port',
          request,
          "200 OK",
          "Hello, World!")
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestSSLKeepAliveClient(h', sslctx, port')
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client =
          _TestSSLHTTPClientExpectClose(
          h',
          sslctx,
          port',
          request,
          "200 OK")
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestSSLHTTPClient(
          h',
          sslctx,
          port',
          "GARBAGE DATA\r\n\r\n",
          "400 Bad Request",
          None)
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestStreamServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestSSLStreamClient(h', sslctx, port')
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

actor \nodoc\ _TestSSLHTTPClient is
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
    _tcp_connection =
      lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
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
    _h.fail("SSL client connection failed")
    _h.complete(false)

  fun ref _verify_response() =>
    _completed = true
    let response: String val = _response.clone()

    if not response.contains(_expected_status) then
      _h.fail("Expected status '" + _expected_status +
        "' not found in response:\n" + response)
      _h.complete(false)
      return
    end

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
    _tcp_connection =
      lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

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
      let response: String val = _response.clone()
      if response.contains(_expected_status) then
        _h.complete(true)
      else
        _h.fail("Connection closed before valid response received")
        _h.complete(false)
      end
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("SSL client connection failed")
    _h.complete(false)

actor \nodoc\ _TestSSLKeepAliveClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _requests_sent: USize = 0
  var _completed: Bool = false

  new create(
    h: TestHelper,
    ssl_ctx: ssl_net.SSLContext val,
    port: String)
  =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

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
      try
        r.find("Hello, World!")?
        _requests_sent = 2
        _tcp_connection.send(
          "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n")
      end
    elseif _requests_sent == 2 then
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
    _h.fail("SSL client connection failed")
    _h.complete(false)

actor \nodoc\ _TestSSLStreamClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _completed: Bool = false

  new create(
    h: TestHelper,
    ssl_ctx: ssl_net.SSLContext val,
    port: String)
  =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.ssl_client(
      lori.TCPConnectAuth(_h.env.root), ssl_ctx, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    if r.contains("0\r\n\r\n") then
      _completed = true
      if not (r.contains("Transfer-Encoding: chunked") or
        r.contains("transfer-encoding: chunked"))
      then
        _h.fail(
          "Missing Transfer-Encoding: chunked header in:\n" + r)
        _h.complete(false)
        return lori.KeepReading
      end
      if not (r.contains("chunk1") and r.contains("chunk2") and
        r.contains("chunk3"))
      then
        _h.fail("Missing chunk data in:\n" + r)
        _h.complete(false)
        return lori.KeepReading
      end
      _h.complete(true)
    end
    lori.KeepReading

  fun ref _on_closed() =>
    // A close after the test's outcome is decided is not a failure.
    if not _completed then
      _h.fail(
        "Connection closed before the chunked response completed:\n" +
          _response)
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("SSL stream client connection failed")
    _h.complete(false)

class \nodoc\ iso _TestSSLStartFailure is UnitTest
  """
  Connect a plain TCP client to an SSL server. The SSL handshake fails,
  triggering `on_start_failure(StartFailedSSL)` on the server actor.
  Verifies the callback fires instead of silently swallowing the failure.
  """
  fun name(): String => "server/ssl start failure"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let sslctx =
      try _TestSSLContext(h.env.root)?
      else
        h.fail("Unable to set up SSL context")
        h.complete(false)
        return
      end
    let port = "45913"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestStartFailureServerFactory(h),
      config,
      {(h': TestHelper, port': String) =>
        // Connect with plain TCP (no SSL) to trigger SSL handshake failure
        let client = _TestPlainTCPClient(h', port')
        h'.dispose_when_done(client)
      }
      where ssl_ctx = sslctx)
    h.dispose_when_done(listener)

class \nodoc\ val _TestStartFailureServerFactory is _TestConnectionFactory
  let _h: TestHelper

  new val create(h: TestHelper) =>
    _h = h

  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestStartFailureServer(auth, fd, config, ssl_ctx, _h)

actor \nodoc\ _TestStartFailureServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  let _h: TestHelper

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None),
    h: TestHelper)
  =>
    _h = h
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_start_failure(reason: lori.StartFailureReason) =>
    match \exhaustive\ reason
    | lori.StartFailedSSL => _h.complete(true)
    end

actor \nodoc\ _TestPlainTCPClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  Plain TCP client that sends non-SSL data to trigger a handshake
  failure on an SSL server.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()

  new create(h: TestHelper, port: String) =>
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    None

  fun ref _on_connected() =>
    _tcp_connection.send("NOT AN SSL HANDSHAKE\r\n")

