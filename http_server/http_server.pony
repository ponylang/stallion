"""
HTTP server for Pony, built on lori.

Start a server with `Server`, passing a `HandlerFactory` and `ServerConfig`.
Use `Responder.respond()` to send responses:

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
  fun ref request_complete(responder: Responder) =>
    responder.respond(StatusOK, None, "Hello!")
```

For streaming responses, use chunked transfer encoding:

```pony
class ref StreamHandler is Handler
  fun ref request_complete(responder: Responder) =>
    responder.start_chunked_response(StatusOK)
    responder.send_chunk("chunk 1")
    responder.send_chunk("chunk 2")
    responder.finish_response()
```
"""
