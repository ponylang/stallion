use stallion = "../../stallion"
use "net"

actor Main
  new create(env: Env) =>
    let auth = TCPListenAuth(env.root)
    Listener(auth, "0.0.0.0", "8080", env.out)

actor Listener is TCPListenerActor
  """
  TCP listener that creates `StreamServer` actors for each connection.
  """
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _config: stallion.ServerConfig
  let _server_auth: TCPServerAuth

  new create(
    auth: TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = TCPListener(auth, host, port, this)

  fun ref _listener(): TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): TCPConnectionActor =>
    StreamServer(_server_auth, fd, _config)

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

actor StreamServer is stallion.HTTPServerActor
  """
  Streams a five-chunk response using chunked transfer encoding.
  """
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  var _responder: (stallion.Responder | None) = None
  var _chunks_sent: USize = 0

  new create(
    auth: TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig)
  =>
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request(
    request': stallion.Request val,
    responder: stallion.Responder)
  =>
    let headers =
      recover val
        stallion.Headers
          .> set("content-type", "text/plain")
      end
    match \exhaustive\ responder.start_chunked_response(
      stallion.StatusOK, headers)
    | stallion.StreamingStarted =>
      responder.send_chunk("chunk 1 of 5\n")
      _responder = responder
      _chunks_sent = 1
    | stallion.ChunkedNotSupported =>
      let body: String val = "Chunked encoding not supported"
      let response = stallion.ResponseBuilder(stallion.StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", body.size().string())
        .finish_headers()
        .add_chunk(body)
        .build()
      responder.respond(response)
    | stallion.AlreadyResponded => None
    | stallion.ConnectionClosed => None
    end

  fun ref on_chunk_sent(token: stallion.ChunkSendToken) =>
    match _responder
    | let r: stallion.Responder =>
      _chunks_sent = _chunks_sent + 1
      if _chunks_sent <= 5 then
        r.send_chunk("chunk " + _chunks_sent.string() + " of 5\n")
      end
      if _chunks_sent == 5 then
        r.finish_response()
      end
    end
