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
  match responder.start_chunked_response(stallion.StatusOK)
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

Cookies are automatically parsed from `Cookie` request headers and available
via `request'.cookies`. Use `stallion.ParseCookies` for direct parsing, and
`stallion.SetCookieBuilder` to construct validated `Set-Cookie` response headers
with secure defaults:

```pony
fun ref on_request_complete(request': stallion.Request val,
  responder: stallion.Responder)
=>
  // Read a cookie from the request
  let session = match request'.cookies.get("session")
  | let s: String val => s
  else "anonymous"
  end

  // Build a Set-Cookie header (defaults: Secure, HttpOnly, SameSite=Lax)
  match stallion.SetCookieBuilder("session", "new-token")
    .with_path("/")
    .with_max_age(3600)
    .build()
  | let sc: stallion.SetCookie val =>
    let body: String val = "Hello, " + session + "!"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Length", body.size().string())
      .add_header("Set-Cookie", sc.header_value())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
  | let err: stallion.SetCookieBuildError =>
    // Handle validation error
    None
  end
```

For content negotiation, use `stallion.ContentNegotiation` to select a
response content type based on the client's `Accept` header. This is opt-in —
most endpoints serve a single content type, so automatic parsing would waste
CPU. Call it only in handlers that support multiple formats:

```pony
fun ref on_request_complete(request': stallion.Request val,
  responder: stallion.Responder)
=>
  let supported = [as stallion.MediaType val:
    stallion.MediaType("application", "json")
    stallion.MediaType("text", "plain")
  ]
  match stallion.ContentNegotiation.from_request(request', supported)
  | let mt: stallion.MediaType val =>
    // Respond with the negotiated content type
    let body: String val = "Hello!"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", mt.string())
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
  | stallion.NoAcceptableType =>
    // 406 Not Acceptable
    let body: String val = "Not Acceptable"
    let response = stallion.ResponseBuilder(
        stallion.StatusNotAcceptable)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
  end
```

For one-shot timers (request processing deadlines, application-level timeouts),
use `stallion.HTTPServer.set_timer()`. Unlike idle timeout, this timer fires
unconditionally — I/O activity does not reset it. Only one timer can be active
per connection at a time. The typical pattern is a processing deadline: set a
timer, delegate work to another actor, and race the result against the deadline:

```pony
actor MyServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _database: Database tag
  var _timer: (lori.TimerToken | None) = None
  var _responder: (stallion.Responder | None) = None

  // ... constructor ...

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    match lori.MakeTimerDuration(5_000)
    | let d: lori.TimerDuration =>
      match _http.set_timer(d)
      | let t: lori.TimerToken =>
        _timer = t
        _responder = responder
        _database.query(request', this)
      | let err: lori.SetTimerError => None
      end
    end

  be query_result(data: String val) =>
    // Work completed before the deadline — cancel timer and respond
    match (_timer, _responder)
    | (let t: lori.TimerToken, let r: stallion.Responder) =>
      _http.cancel_timer(t)
      _timer = None
      _responder = None
      let response = stallion.ResponseBuilder(stallion.StatusOK)
        .add_header("Content-Length", data.size().string())
        .finish_headers()
        .add_chunk(data)
        .build()
      r.respond(response)
    end

  fun ref on_timer(token: lori.TimerToken) =>
    // Deadline expired — worker didn't finish in time
    match (_timer, _responder)
    | (let t: lori.TimerToken, let r: stallion.Responder) if t == token =>
      _timer = None
      _responder = None
      let body: String val = "Request timed out"
      let response = stallion.ResponseBuilder(stallion.StatusRequestTimeout)
        .add_header("Content-Length", body.size().string())
        .finish_headers()
        .add_chunk(body)
        .build()
      r.respond(response)
    end
```
"""
