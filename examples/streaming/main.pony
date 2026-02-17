"""
HTTP server that streams responses using chunked transfer encoding.

Demonstrates the streaming response API: `start_chunked_response()`,
`send_chunk()`, and `finish_response()`. Each request receives three
chunks before the response is finalized.

Note: this demonstrates streaming *responses*, not streaming request
bodies. It uses the buffered `Handler` trait since it doesn't need
incremental request body access.
"""
use http_server = "../../http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config = http_server.ServerConfig("localhost", "8080")
    http_server.Server(auth, _StreamFactory, config, _ServerNotify(env))

class val _ServerNotify is http_server.ServerNotify
  let _env: Env
  new val create(env: Env) => _env = env

  fun listening(server: http_server.Server tag) =>
    _env.out.print("Server listening on localhost:8080")

  fun listen_failure(server: http_server.Server tag) =>
    _env.out.print("Failed to start server")

  fun closed(server: http_server.Server tag) =>
    _env.out.print("Server closed")

class val _StreamFactory is http_server.HandlerFactory
  fun apply(): http_server.Handler ref^ =>
    _StreamHandler

class ref _StreamHandler is http_server.Handler
  var _request_count: USize = 0

  fun ref request_complete(
    responder: http_server.Responder,
    body: http_server.RequestBody)
  =>
    _request_count = _request_count + 1
    let headers = recover val
      let h = http_server.Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.start_chunked_response(http_server.StatusOK, headers)
    responder.send_chunk("chunk 1 of request " + _request_count.string() + "\n")
    responder.send_chunk("chunk 2 of request " + _request_count.string() + "\n")
    responder.send_chunk("chunk 3 of request " + _request_count.string() + "\n")
    responder.finish_response()
