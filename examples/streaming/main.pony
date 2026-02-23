"""
HTTP server that streams responses using chunked transfer encoding with
flow-controlled delivery driven by `on_chunk_sent()` callbacks.

Demonstrates the streaming response API: `start_chunked_response()`,
`send_chunk()`, `finish_response()`, and `on_chunk_sent()`. The actor sends
the first chunk in `on_request()`, then each `on_chunk_sent()` callback
drives the next chunk. This ensures the OS has accepted each chunk before
sending the next — natural backpressure without timers or manual windowing.

Note: this demonstrates streaming *responses*, not streaming request
bodies. Request body data arrives via `on_body_chunk()` callbacks — this
example ignores request bodies.
"""
use stallion = "../../stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    Listener(auth, "0.0.0.0", "8080", env.out)

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
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  var _responder: (stallion.Responder | None) = None
  var _chunks_sent: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig)
  =>
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    let headers = recover val
      let h = stallion.Headers
      h.set("content-type", "text/plain")
      h
    end
    match responder.start_chunked_response(stallion.StatusOK, headers)
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
