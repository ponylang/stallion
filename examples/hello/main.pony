"""
Basic HTTP server that responds to every request with "Hello, World!".

Demonstrates the core API: a listener actor implements
`lori.TCPListenerActor` and creates `HTTPServerActor` instances in
`_on_accept`. Also demonstrates query parameter extraction from the
pre-parsed URI: a `?name=X` parameter customizes the greeting.

Body data arrives via `on_body_chunk()` callbacks. This example ignores
request bodies — for body accumulation, see the streaming example.
"""
use stallion = "../../stallion"
use uri = "uri"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    Listener(auth, "localhost", "8080", env.out)

actor Listener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _out: OutStream
  let _config: stallion.ServerConfig
  let _server_auth: lori.TCPServerAuth

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    HelloServer(_server_auth, fd, _config)

  fun ref _on_listening() =>
    try
      (let host, let port) = _tcp_listener.local_address().name()?
      _out.print("Server listening on " + host + ":" + port)
    else
      _out.print("Server listening")
    end

  fun ref _on_listen_failure() =>
    _out.print("Failed to start server")

  fun ref _on_closed() =>
    _out.print("Server closed")

actor HelloServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig)
  =>
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    // Extract a "name" query parameter if present
    var name: String val = "World"
    match request'.uri.query_params()
    | let params: uri.QueryParams val =>
      match params.get("name")
      | let n: String => name = n
      end
    end
    let resp_body: String val = "Hello, " + name + "!"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)
