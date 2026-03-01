"""
HTTP server for Pony, built on lori.

A listener actor implements `lori.TCPListenerActor` and creates
`stallion.HTTPServerActor` instances in `_on_accept`. Each connection actor owns
a `stallion.HTTPServer` that handles HTTP parsing and response management,
delivering HTTP events via `stallion.HTTPServerLifecycleEventReceiver` callbacks.

```pony
use stallion = "stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    MyListener(auth, "localhost", "8080")

actor MyListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig

  new create(auth: lori.TCPListenAuth, host: String, port: String) =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config)

actor MyServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: stallion.ServerConfig)
  =>
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    let body: String val = "Hello!"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
```

For streaming responses, use chunked transfer encoding.
`start_chunked_response()` returns a `stallion.StartChunkedResponseResult`
indicating success or the reason for failure. Each `send_chunk()` returns a
`stallion.ChunkSendToken` — override `on_chunk_sent()` to drive flow-controlled
delivery:

```pony
fun ref on_request_complete(request': stallion.Request val,
  responder: stallion.Responder)
=>
  match \exhaustive\ responder.start_chunked_response(stallion.StatusOK)
  | stallion.StreamingStarted =>
    let token = responder.send_chunk("chunk 1")
    // When on_chunk_sent(token) fires, send the next chunk...
    responder.send_chunk("chunk 2")
    responder.finish_response()
  | stallion.ChunkedNotSupported =>
    // HTTP/1.0 — fall back to a complete response
    responder.respond(fallback_response)
  | stallion.AlreadyResponded => None
  end
```

For HTTPS, use `stallion.HTTPServer.ssl` instead of `stallion.HTTPServer`. Store
an `SSLContext val` in the listener and pass it through in `_on_accept`:

```pony
use stallion = "stallion"
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
  let _config: stallion.ServerConfig
  let _ssl_ctx: SSLContext val

  new create(auth: lori.TCPListenAuth, host: String, port: String,
    ssl_ctx: SSLContext val)
  =>
    _ssl_ctx = ssl_ctx
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config, _ssl_ctx)
```

The actor explicitly chooses `stallion.HTTPServer` (plain HTTP) or
`stallion.HTTPServer.ssl` (HTTPS) in its constructor. The `MyServer` actor in
the HTTPS example would use
`stallion.HTTPServer.ssl(auth, ssl_ctx, fd, this, config)` instead of
`stallion.HTTPServer(auth, fd, this, config)`.
"""
