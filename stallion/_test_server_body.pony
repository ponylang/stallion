use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"
use uri = "uri"

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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestURIParsingServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET /hello?name=test HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
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
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let uri_query: String val =
      match \exhaustive\ request'.uri.query
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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestConnectURIServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
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
    _http =
      match ssl_ctx
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
      port =
        match \exhaustive\ a.port
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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestBodyServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "POST / HTTP/1.1\r\nHost: localhost\r\n" +
          "Content-Length: 13\r\n\r\nHello, Body!\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
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
    _http =
      match ssl_ctx
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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestBodyServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestBodyServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "POST / HTTP/1.1\r\nHost: localhost\r\n" +
          "Content-Length: 0\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
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
    let listener =
      _TestServerListener(
      h,
      port,
      _TestBodyServerFactory,
      config,
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

class \nodoc\ iso _TestServerCookieParsing is UnitTest
  """
  Send a request with a Cookie header, verify the server reads the cookies
  from request'.cookies and includes the values in the response body.
  """
  fun name(): String => "server/cookie parsing"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45910"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestCookieServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "GET / HTTP/1.1\r\nHost: localhost\r\n" +
          "Cookie: session=abc123; theme=dark\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
          "session=abc123,theme=dark")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestCookieServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestCookieServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestCookieServer is HTTPServerActor
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
    // Build response body from parsed cookies
    let session =
      match request'.cookies.get("session")
      | let s: String val => s
    else "missing"
    end
    let theme =
      match request'.cookies.get("theme")
      | let s: String val => s
    else "missing"
    end
    let resp_body: String val =
      "session=" + session + ",theme=" + theme
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

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
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    if (not _got_first) and r.contains("first") then
      _got_first = true
    end
    if (not _got_second) and r.contains("second") then
      _got_second = true
    end
    lori.KeepReading

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

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

