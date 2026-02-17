"""
Basic HTTP server that responds to every request with "Hello, World!".

Demonstrates the core API: `Server`, `HandlerFactory`, `Handler`,
`Responder`, `ServerConfig`, and `ServerNotify`. Also demonstrates
query parameter extraction from the pre-parsed URI: a `?name=X`
parameter customizes the greeting.
"""
use http_server = "../../http_server"
use uri = "../../http_server/uri"
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
  fun apply(): http_server.Handler ref^ =>
    _HelloHandler

class ref _HelloHandler is http_server.Handler
  var _request_count: USize = 0
  var _name: String val = "World"

  fun ref request(
    method: http_server.Method,
    request_uri: uri.URI val,
    version: http_server.Version,
    headers: http_server.Headers val)
  =>
    // Extract a "name" query parameter if present
    _name = "World"
    match request_uri.query
    | let q: String val =>
      match uri.ParseQueryParameters(q)
      | let params: Array[(String val, String val)] val =>
        for (k, v) in params.values() do
          if k == "name" then _name = v end
        end
      end
    end

  fun ref request_complete(responder: http_server.Responder) =>
    _request_count = _request_count + 1
    let body: String val =
      "Hello, " + _name + "! (request " + _request_count.string() + ")"
    let headers = recover val
      let h = http_server.Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.respond(http_server.StatusOK, headers, body)
