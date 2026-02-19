"""
HTTP server that streams responses using chunked transfer encoding.

Demonstrates the streaming response API: `start_chunked_response()`,
`send_chunk()`, and `finish_response()`. Each request receives three
chunks before the response is finalized.

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
    StreamServer(_server_auth, fd, _config, None, None)

  fun ref _on_listening() =>
    _out.print("Server listening on localhost:8080")

  fun ref _on_listen_failure() =>
    _out.print("Failed to start server")

  fun ref _on_closed() =>
    _out.print("Server closed")

actor StreamServer is http_server.HTTPServerActor
  var _http: http_server.HTTPServer = http_server.HTTPServer.none()
  var _request_count: USize = 0

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

  fun ref request_complete(responder: http_server.Responder) =>
    _request_count = _request_count + 1
    let headers = recover val
      let h = http_server.Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.start_chunked_response(http_server.StatusOK, headers)
    responder.send_chunk(
      "chunk 1 of request " + _request_count.string() + "\n")
    responder.send_chunk(
      "chunk 2 of request " + _request_count.string() + "\n")
    responder.send_chunk(
      "chunk 3 of request " + _request_count.string() + "\n")
    responder.finish_response()
