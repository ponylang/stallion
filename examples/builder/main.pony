"""
HTTP server using ResponseBuilder to construct responses dynamically.

Demonstrates `ResponseBuilder` for building and sending HTTP responses.
The builder constructs the response as a single byte array via a typed
state machine that guides the caller through status, headers, then body.
Send the built response via `Responder.respond()`.
"""
// In user code with corral, this would be: use http_server = "http_server"
use http_server = "../../http_server"
use uri = "uri"
use lori = "lori"
use ssl_net = "ssl/net"
use "time"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    Listener(auth, "localhost", "8080", env.out)

actor Listener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _out: OutStream
  let _config: http_server.ServerConfig
  let _server_auth: lori.TCPServerAuth

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = lori.TCPServerAuth(auth)
    _config = http_server.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    HelloServer(_server_auth, fd, _config, None, None)

  fun ref _on_listening() =>
    try
      (let host, let port) = _tcp_listener.local_address().name()?
      _out.print("Builder example listening on " + host + ":" + port)
    else
      _out.print("Builder example listening")
    end

  fun ref _on_listen_failure() =>
    _out.print("Failed to start server")

  fun ref _on_closed() =>
    _out.print("Server closed")

actor HelloServer is http_server.HTTPServerActor
  var _http: http_server.HTTPServer = http_server.HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: http_server.ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None),
    timers: (Timers | None))
  =>
    _http = http_server.HTTPServer(auth, fd, ssl_ctx, this,
      config, timers)

  fun ref _http_connection(): http_server.HTTPServer => _http

  fun ref request_complete(request': http_server.Request val,
    responder: http_server.Responder)
  =>
    var name: String val = "World"
    match request'.uri.query_params()
    | let params: uri.QueryParams val =>
      match params.get("name")
      | let n: String => name = n
      end
    end
    let resp_body: String val = "Hello, " + name + "!"
    let response = http_server.ResponseBuilder(http_server.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)
