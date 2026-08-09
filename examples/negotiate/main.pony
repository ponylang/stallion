use stallion = "../../stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    Listener(auth, "0.0.0.0", "8080", env.out)

actor Listener is lori.TCPListenerActor
  """
  TCP listener that creates `NegotiateServer` actors for each connection.
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
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    NegotiateServer(_server_auth, fd, _config)

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

actor NegotiateServer is stallion.HTTPServerActor
  """
  Selects a response format based on the client's Accept header.
  """
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _supported: Array[stallion.MediaType val] val

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig)
  =>
    _supported =
      [ as stallion.MediaType val:
        stallion.MediaType("application", "json")
        stallion.MediaType("text", "plain")
      ]
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(
    request': stallion.Request val,
    responder: stallion.Responder)
  =>
    match \exhaustive\ stallion.ContentNegotiation.from_request(
      request', _supported)
    | let mt: stallion.MediaType val =>
      _respond_with(mt, responder)
    | stallion.NoAcceptableType =>
      _respond_not_acceptable(responder)
    end

  fun _respond_with(
    media_type: stallion.MediaType val,
    responder: stallion.Responder ref)
  =>
    let body: String val =
      if media_type.subtype == "json" then
        """{"message": "Hello, World!"}"""
      else
        "Hello, World!"
      end

    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", media_type.string())
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

  fun _respond_not_acceptable(responder: stallion.Responder ref) =>
    let body: String val = "Not Acceptable"
    let response = stallion.ResponseBuilder(stallion.StatusNotAcceptable)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
