"""
Basic HTTP server that responds to every request with "Hello, World!".

Demonstrates the core API: `Server`, `HandlerFactory`, `Handler`, and
`Responder`.
"""
use http_server = "../../http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    http_server.Server(auth, "localhost", "8080", _HelloFactory)
    env.out.print("HTTP server listening on localhost:8080")

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
