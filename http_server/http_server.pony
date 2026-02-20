"""
HTTP server for Pony, built on lori.

A listener actor implements `lori.TCPListenerActor` and creates
`HTTPServerActor` instances in `_on_accept`. Each connection actor owns
an `HTTPServer` that handles HTTP parsing and response management,
delivering HTTP events via `HTTPServerLifecycleEventReceiver` callbacks.

```pony
use "http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    MyListener(auth, "localhost", "8080")

actor MyListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ServerConfig

  new create(auth: lori.TCPListenAuth, host: String, port: String) =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config, None, None)

actor MyServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None),
    timers: (Timers | None))
  =>
    _http = HTTPServer(auth, fd, ssl_ctx, this, config, timers)

  fun ref _http_connection(): HTTPServer => _http

  fun ref request_complete(request': Request val,
    responder: Responder)
  =>
    let body: String val = "Hello!"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
```

For streaming responses, use chunked transfer encoding:

```pony
fun ref request_complete(request': Request val,
  responder: Responder)
=>
  responder.start_chunked_response(StatusOK)
  responder.send_chunk("chunk 1")
  responder.send_chunk("chunk 2")
  responder.finish_response()
```

For HTTPS, store an `SSLContext val` in the listener and pass it through
in `_on_accept`:

```pony
use "http_server"
use "files"
use "ssl/net"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let sslctx = recover val
      SSLContext
        .> set_cert(
          FilePath(FileAuth(env.root), "cert.pem"),
          FilePath(FileAuth(env.root), "key.pem"))?
        .> set_client_verify(false)
        .> set_server_verify(false)
    end
    let auth = lori.TCPListenAuth(env.root)
    MyListener(auth, "localhost", "8443", sslctx)

actor MyListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ServerConfig
  let _ssl_ctx: SSLContext val

  new create(auth: lori.TCPListenAuth, host: String, port: String,
    ssl_ctx: SSLContext val)
  =>
    _ssl_ctx = ssl_ctx
    _server_auth = lori.TCPServerAuth(auth)
    _config = ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config, _ssl_ctx, None)
```

Actors are identical for HTTP and HTTPS — SSL is handled transparently
by the protocol layer.
"""
