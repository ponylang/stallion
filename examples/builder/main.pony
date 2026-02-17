"""
HTTP server using ResponseBuilder to construct responses dynamically.

Demonstrates `ResponseBuilder` for building and sending HTTP responses.
The builder constructs the response as a single byte array via a typed
state machine that guides the caller through status, headers, then body.
Send the built response via `Responder.respond_raw()`.
"""
// In user code with corral, this would be: use http_server = "http_server"
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
    _env.out.print("Builder example listening on localhost:8080")

  fun listen_failure(server: http_server.Server tag) =>
    _env.out.print("Failed to start server")

  fun closed(server: http_server.Server tag) =>
    _env.out.print("Server closed")

class val _HelloFactory is http_server.HandlerFactory
  fun apply(): http_server.Handler ref^ =>
    _HelloHandler

class ref _HelloHandler is http_server.Handler
  var _name: String val = "World"

  fun ref request(r: http_server.Request val) =>
    _name = "World"
    match r.uri.query_params()
    | let params: uri.QueryParams val =>
      match params.get("name")
      | let name: String => _name = name
      end
    end

  fun ref request_complete(
    responder: http_server.Responder,
    body: http_server.RequestBody)
  =>
    let resp_body: String val = "Hello, " + _name + "!"
    let response = http_server.ResponseBuilder(http_server.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond_raw(response)
