"""
HTTPS server that responds to every request with "Hello, World!".

Demonstrates SSL/TLS support: creating an `SSLContext`, loading certificate
and key files, and passing the context to `Server`. Handlers are identical
to plaintext HTTP — SSL is handled transparently by the connection layer.

Must be run from the project root so the relative certificate paths resolve
correctly. Test with `curl -k https://localhost:8443/`.
"""
use "files"
use "ssl/net"
use http_server = "../../http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        recover val
          SSLContext
            .> set_authority(
              FilePath(file_auth, "assets/cert.pem"))?
            .> set_cert(
              FilePath(file_auth, "assets/cert.pem"),
              FilePath(file_auth, "assets/key.pem"))?
            .> set_client_verify(false)
            .> set_server_verify(false)
        end
      else
        env.out.print("Unable to set up SSL context")
        return
      end

    let auth = lori.TCPListenAuth(env.root)
    let config = http_server.ServerConfig("localhost", "8443")
    http_server.Server(auth, _HelloFactory, config, _ServerNotify(env)
      where ssl_ctx = sslctx)

class val _ServerNotify is http_server.ServerNotify
  let _env: Env
  new val create(env: Env) => _env = env

  fun listening(server: http_server.Server tag) =>
    _env.out.print("HTTPS server listening on localhost:8443")

  fun listen_failure(server: http_server.Server tag) =>
    _env.out.print("Failed to start server")

  fun closed(server: http_server.Server tag) =>
    _env.out.print("Server closed")

class val _HelloFactory is http_server.HandlerFactory
  fun apply(): http_server.Handler ref^ =>
    _HelloHandler

class ref _HelloHandler is http_server.Handler
  fun ref request_complete(
    responder: http_server.Responder,
    body: http_server.RequestBody)
  =>
    let headers = recover val
      let h = http_server.Headers
      h.set("content-type", "text/plain")
      h
    end
    responder.respond(http_server.StatusOK, headers, "Hello, World!")
