"""
HTTP server that streams responses using chunked transfer encoding.

Demonstrates the streaming response API: `start_chunked_response()`,
`send_chunk()`, and `finish_response()`. A timer drives chunk delivery
at one-second intervals, simulating a response where data becomes
available over time (e.g., progress updates, log tailing, or results
from a long-running computation). The actor receives the `Responder` in
`request()` and stores it across behavior turns, sending chunks as timer
messages arrive.

Note: this demonstrates streaming *responses*, not streaming request
bodies. Request body data arrives via `body_chunk()` callbacks — this
example ignores request bodies.
"""
use http_server = "../../http_server"
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
  let _timers: Timers

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = lori.TCPServerAuth(auth)
    _config = http_server.ServerConfig(host, port)
    _timers = Timers
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    StreamServer(_server_auth, fd, _config, None, _timers)

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

actor StreamServer is http_server.HTTPServerActor
  let _timers: Timers
  var _http: http_server.HTTPServer = http_server.HTTPServer.none()
  var _responder: (http_server.Responder | None) = None
  var _chunks_sent: USize = 0
  var _chunk_timer: (Timer tag | None) = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: http_server.ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None),
    timers: Timers)
  =>
    _timers = timers
    _http = http_server.HTTPServer(auth, fd, ssl_ctx, this,
      config, timers)

  fun ref _http_connection(): http_server.HTTPServer => _http

  fun ref request(request': http_server.Request val,
    responder: http_server.Responder)
  =>
    let headers = recover val
      let h = http_server.Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.start_chunked_response(http_server.StatusOK, headers)
    responder.send_chunk("chunk 1 of 5\n")
    _responder = responder
    _chunks_sent = 1
    // Send remaining chunks at one-second intervals
    let timer = Timer(_ChunkNotify(this), 1_000_000_000, 1_000_000_000)
    _chunk_timer = timer
    _timers(consume timer)

  be _send_chunk() =>
    match _responder
    | let r: http_server.Responder =>
      _chunks_sent = _chunks_sent + 1
      r.send_chunk("chunk " + _chunks_sent.string() + " of 5\n")
      if _chunks_sent == 5 then
        r.finish_response()
        _cancel_chunk_timer()
      end
    end

  fun ref closed() =>
    _cancel_chunk_timer()

  fun ref _cancel_chunk_timer() =>
    match _chunk_timer
    | let t: Timer tag => _timers.cancel(t)
    end
    _chunk_timer = None
    _responder = None

class _ChunkNotify is TimerNotify
  let _server: StreamServer tag

  new iso create(server: StreamServer tag) =>
    _server = server

  fun ref apply(timer: Timer, count: U64): Bool =>
    _server._send_chunk()
    true

  fun ref cancel(timer: Timer) =>
    None
