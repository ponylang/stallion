"""
HTTP server for Pony, built on lori.

Start a server with `Server`, passing a `HandlerFactory` that creates a
`Handler` for each connection. Use `Responder.respond()` to send responses:

```pony
use "http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    Server(lori.TCPListenAuth(env.root), "localhost", "8080", MyFactory)

class val MyFactory is HandlerFactory
  fun apply(responder: Responder): Handler ref^ =>
    MyHandler(responder)

class ref MyHandler is Handler
  let _responder: Responder
  new ref create(responder: Responder) => _responder = responder

  fun ref request_complete() =>
    _responder.respond(StatusOK, None, "Hello!")
```
"""
