"""
HTTPS server that responds to every request with "Hello, World!".

Demonstrates SSL/TLS support: creating an `SSLContext`, loading certificate
and key files, and passing the context to connection actors via `_on_accept`.
The `HTTPServer` handles SSL dispatch internally — actors are identical for
HTTP and HTTPS.

Must be run from the project root so the relative certificate paths resolve
correctly. Test with `curl -k https://localhost:8443/`.
"""
use "files"
use "ssl/net"
use http_server = "../../http_server"
use lori = "lori"
use "time"

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
    Listener(auth, "localhost", "8443", env.out, sslctx)

actor Listener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _out: OutStream
  let _config: http_server.ServerConfig
  let _server_auth: lori.TCPServerAuth
  let _ssl_ctx: SSLContext val

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    out: OutStream,
    ssl_ctx: SSLContext val)
  =>
    _out = out
    _ssl_ctx = ssl_ctx
    _server_auth = lori.TCPServerAuth(auth)
    _config = http_server.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    HelloServer(_server_auth, fd, _config, _ssl_ctx, None)

  fun ref _on_listening() =>
    _out.print("HTTPS server listening on localhost:8443")

  fun ref _on_listen_failure() =>
    _out.print("Failed to start server")

  fun ref _on_closed() =>
    _out.print("Server closed")

actor HelloServer is http_server.HTTPServerActor
  var _http: http_server.HTTPServer = http_server.HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: http_server.ServerConfig,
    ssl_ctx: (SSLContext val | None),
    timers: (Timers | None))
  =>
    _http = http_server.HTTPServer(auth, fd, ssl_ctx, this,
      config, timers)

  fun ref _http_connection(): http_server.HTTPServer => _http

  fun ref request_complete(responder: http_server.Responder) =>
    let resp_body: String val = "Hello, World!"
    let response = http_server.ResponseBuilder(http_server.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)
