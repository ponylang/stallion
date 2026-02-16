"""
Basic HTTP server that responds to every request with "Hello, World!".

Demonstrates the core API: `Server`, `HandlerFactory`, `Handler`,
`Responder`, `ServerConfig`, and `ServerNotify`.
"""
use http_server = "../../http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config = http_server.ServerConfig("localhost", "8080")
    http_server.Server(auth, _HelloFactory, config, _ServerNotify(env))

class val _ServerNotify is http_server.ServerNotify
  let _env: Env
  new val create(env: Env) => _env = env

  fun listening(server: http_server.Server tag) =>
    _env.out.print("Server listening on localhost:8080")

  fun listen_failure(server: http_server.Server tag) =>
    _env.out.print("Failed to start server")

class val _HelloFactory is http_server.HandlerFactory
  fun apply(responder: http_server.Responder): http_server.Handler ref^ =>
    _HelloHandler(responder)

class ref _HelloHandler is http_server.Handler
  let _responder: http_server.Responder

  new ref create(responder: http_server.Responder) =>
    _responder = responder

  fun ref request_complete() =>
    let headers = recover val
      let h = http_server.Headers
      h.set("content-type", "text/plain")
      h.set("content-length", "13")
      h
    end
    _responder.respond(http_server.StatusOK, headers, "Hello, World!")
