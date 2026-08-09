use stallion = "../../stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    Listener(auth, "0.0.0.0", "8080", env.out)

actor Listener is lori.TCPListenerActor
  """
  TCP listener that creates `ReadBufferServer` actors for each connection.
  """
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
    _config =
      match lori.MakeReadBufferSize(1024)
      | let b: lori.ReadBufferSize =>
        stallion.ServerConfig(host, port where read_buffer_size' = b)
      else
        // 1024 is greater than zero, so this cannot happen.
        stallion.ServerConfig(host, port)
      end
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    ReadBufferServer(_server_auth, fd, _config, _out)

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

actor ReadBufferServer is stallion.HTTPServerActor
  """
  Responds to each request with an incrementing counter.
  """
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _out: OutStream
  var _request_count: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig,
    out: OutStream)
  =>
    _out = out
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(
    request': stallion.Request val,
    responder: stallion.Responder)
  =>
    """
    Responds with a numbered request counter.
    """
    _request_count = _request_count + 1
    let body: String val = "Request " + _request_count.string() + "\n"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
