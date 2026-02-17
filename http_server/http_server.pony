"""
HTTP server for Pony, built on lori.

Start a server with `Server`, passing a handler factory and `ServerConfig`.

Most handlers should use `Handler` (buffered), where the complete request
body is delivered in `request_complete`:

```pony
use "http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let config = ServerConfig("localhost", "8080")
    Server(lori.TCPListenAuth(env.root), MyFactory, config)

class val MyFactory is HandlerFactory
  fun apply(): Handler ref^ =>
    MyHandler

class ref MyHandler is Handler
  fun ref request_complete(responder: Responder, body: RequestBody) =>
    responder.respond(StatusOK, None, "Hello!")
```

For streaming request bodies (large uploads, proxying), use
`StreamingHandler` where body data arrives incrementally via
`body_chunk()`:

```pony
class val MyStreamingFactory is StreamingHandlerFactory
  fun apply(): StreamingHandler ref^ =>
    MyStreamingHandler

class ref MyStreamingHandler is StreamingHandler
  fun ref body_chunk(data: Array[U8] val) =>
    // process data incrementally
    None

  fun ref request_complete(responder: Responder) =>
    responder.respond(StatusOK, None, "Done!")
```

For streaming responses, use chunked transfer encoding:

```pony
class ref ChunkedResponseHandler is Handler
  fun ref request_complete(responder: Responder, body: RequestBody) =>
    responder.start_chunked_response(StatusOK)
    responder.send_chunk("chunk 1")
    responder.send_chunk("chunk 2")
    responder.finish_response()
```

For HTTPS, pass an `SSLContext val` from the `ssl/net` package:

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
    let config = ServerConfig("localhost", "8443")
    Server(lori.TCPListenAuth(env.root), MyFactory, config
      where ssl_ctx = sslctx)
```

Handlers are identical for HTTP and HTTPS — SSL is handled transparently
by the connection layer.
"""
