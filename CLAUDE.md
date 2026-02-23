# HTTP Server for Pony

## Building

```
make ssl=3.0.x      # build and run tests (OpenSSL 3.x)
make ssl=1.1.x      # build and run tests (OpenSSL 1.1.x)
make ssl=libressl   # build and run tests (LibreSSL)
make clean           # clean build artifacts
```

The `ssl` option is required because this library and lori depend on the `ssl` package.

## Architecture

Package: `stallion` (repo name is `stallion`, Pony package name is `stallion`)

Built on lori (v0.8.4). Lori provides raw TCP I/O with a connection-actor model: `_on_received(data: Array[U8] iso)` for incoming data, `TCPConnection.send(data): (SendToken | SendError)` for outgoing, plus backpressure notifications, SSL support, and per-connection ASIO-level idle timers.

### Key design decisions

**Protocol class pattern (mirrors lori's layering)**: The user's actor IS the connection — no hidden internal actor. The architecture mirrors lori's own layering:

```
lori layer:    TCPConnection (class) + TCPConnectionActor (trait) + ServerLifecycleEventReceiver (trait)
http layer:    HTTPServer (class) + HTTPServerActor (trait) + HTTPServerLifecycleEventReceiver (trait)
```

The user's actor stores `HTTPServer` as a field and implements `HTTPServerActor` (which extends both `TCPConnectionActor` and `HTTPServerLifecycleEventReceiver`). The protocol class handles all HTTP parsing, response queue management, and connection lifecycle — calling back to the user's actor for HTTP-level events. Other actors can communicate directly with the user's actor since it IS the connection actor.

**No HTTP-layer listener wrapper**: A separate listener actor implements `lori.TCPListenerActor` directly, creating `HTTPServerActor` instances in `_on_accept`. Lifecycle callbacks (`_on_listening`, `_on_listen_failure`, `_on_closed`) go directly to the listener actor. This mirrors lori's own echo server pattern — `Main` creates the listener, the listener creates connections. No factory class, no notify class, no hidden internal actor.

**`none()` constructor for field defaults**: `HTTPServer.none()` creates a placeholder instance that allows the `_http` field to have a default value. This is needed because Pony actor constructors require all fields to be initialized before `this` becomes `ref`. Without a default, `this` is `tag` in the constructor body, which can't be passed to `HTTPServer.create()`. The `none()` instance is immediately replaced by `create()` or `ssl()` — its methods are never called.

**Capability chain in the protocol constructors**: Both `HTTPServer.create` (plain HTTP) and `HTTPServer.ssl` (HTTPS) take `server_actor: HTTPServerActor ref` (the user's `this`):
- Stored as `_lifecycle_event_receiver: (HTTPServerLifecycleEventReceiver ref | None)` — for synchronous HTTP callbacks (upcast; `None` for the `none()` placeholder)
- `create` passes to `TCPConnection.server(auth, fd, server_actor, this)` as `TCPConnectionActor ref`; `ssl` passes to `TCPConnection.ssl_server(auth, ssl_ctx, fd, server_actor, this)`
- Protocol passes `this` to `TCPConnection.server()`/`ssl_server()` as `ServerLifecycleEventReceiver ref`

**Parser callback is `ref`, not `tag`**: The parser runs inside the connection actor, so its callback interface uses `fun ref` methods (synchronous calls), not `be` behaviors (actor messages). This avoids the extra actor hop that `ponylang/http_server` requires.

**Trait-based state machines**: State machines (parser and connection lifecycle) follow the pattern from `ponylang/postgres`: states are classes implementing trait hierarchies. Traits for state categories supply default implementations that trap on invalid operations. Each state class owns its per-state data (buffers, accumulators), which is automatically cleaned up on state transitions. Invalid operations are enforced at runtime through trait defaults. The interface width should be adapted to each use case — HTTP needs narrower interfaces than postgres's ~40-method `_SessionState`.

**Relationship to `ponylang/http_server`**: That project is built on the stdlib `net` package and has actor-interaction issues we want to avoid. We may borrow internal logic (e.g., parsing techniques) but the overall architecture and actor interactions are designed fresh around lori's model.

**Connection lifecycle**: Connections are persistent by default (HTTP/1.1 keep-alive). The user's listener creates connections via `_on_accept`, passing `ServerConfig` for parser limits and idle timeout:

```pony
let config = ServerConfig("localhost", "8080")
```

Idle timeout defaults to 60 seconds via `DefaultIdleTimeout`. To customize:

```pony
let timeout = match lori.MakeIdleTimeout(30_000)
| let t: lori.IdleTimeout => t
end
let config = ServerConfig("localhost", "8080" where idle_timeout' = timeout)
```

For HTTPS, pass an `SSLContext val` (from `ssl/net`) to connection actors, which use `HTTPServer.ssl` instead of `HTTPServer`:

```pony
fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
  MyServer(_server_auth, fd, _config, _ssl_ctx)
```

SSL handshake, encryption, and decryption are handled transparently by lori. Actors explicitly choose `HTTPServer(auth, fd, this, config)` for plain HTTP or `HTTPServer.ssl(auth, ssl_ctx, fd, this, config)` for HTTPS.

Connections close when the client sends `Connection: close`, on HTTP/1.0 requests without `Connection: keep-alive`, after a parse error (with the appropriate error status code), when the idle timeout expires, or when the actor calls `HTTPServer.close()`. The `close()` method is the public API for server-initiated connection close — use it after rejecting a request early (e.g., 413 response sent in `on_request()` before body arrives). Backpressure from lori is propagated to the actor via `on_throttled()`/`on_unthrottled()` callbacks and to the response queue via `throttle()`/`unthrottle()`.

**URI parsing in the protocol layer**: The protocol layer parses the raw request-target string into a `URI val` (from the `uri` package, `ponylang/uri`) before delivering it to the actor as part of the `Request val` object. For CONNECT requests, `ParseURIAuthority` parses the authority-form target; for all other methods, `ParseURI` handles origin-form, absolute-form, and asterisk-form targets. Invalid URIs are rejected with 400 Bad Request before reaching the actor. Actors that access URI components (e.g., `request'.uri.query_params()`) need `use "uri"` in their package to name types like `QueryParams`.

**Streaming-only body delivery**: Body data is delivered incrementally via `on_body_chunk()` callbacks on `HTTPServerLifecycleEventReceiver`. Actors that need the complete body accumulate chunks manually. There is no built-in buffering adapter — convenience buffered body delivery is future work per [lori #7](https://github.com/ponylang/lori/issues/7).

**Per-request Responder and response queue**: Each request gets its own `Responder` instance. Both `on_request()` and `on_request_complete()` receive the same `Request val` and `Responder`. Simple servers override only `on_request_complete(request', responder)` — it delivers everything needed to inspect the request and send a response. Override `on_request()` only when you need to respond before the body arrives (e.g., rejecting with 413 Payload Too Large, starting a streaming response). The user's listener creates a new actor per connection in `_on_accept`. Responders send data through a `_ResponseQueue` that ensures pipelined responses are delivered in request order, regardless of the order actors respond. The queue calls back to the protocol via `_ResponseQueueNotify` for TCP I/O — it never holds the TCP connection directly. Responders support two modes: complete (`respond()` with pre-serialized bytes from `ResponseBuilder`) and streaming (`start_chunked_response()` + `send_chunk()` + `finish_response()` using chunked transfer encoding). `start_chunked_response()` returns a `StartChunkedResponseResult` indicating `StreamingStarted`, `ChunkedNotSupported` (HTTP/1.0), or `AlreadyResponded`. `send_chunk()` returns a `ChunkSendToken` (or `None` for no-op cases); the token is delivered to `on_chunk_sent()` when the OS accepts the data, enabling flow-controlled streaming. After connection close, any Responders the actor still holds become inert — their methods route to the closed queue, which no-ops everything.

**Response builder**: `ResponseBuilder` constructs complete HTTP responses as pre-serialized `Array[U8] val` byte arrays, using a typed state machine (via return-type narrowing) to enforce correct construction order: status line, then headers, then body. The builder output is suitable for caching and reuse via `Responder.respond()`, avoiding per-request serialization overhead. The caller is responsible for all response formatting including Content-Length — no headers are injected automatically.

**Idle timeout**: Uses lori's per-connection ASIO-level idle timer (lori 0.8.4+). `_on_started()` calls `_tcp_connection.idle_timeout(config.idle_timeout)` to arm the timer. Lori automatically resets the timer on every send/receive and re-arms after each firing. `HTTPServer._on_idle_timeout()` (from lori's `ServerLifecycleEventReceiver`) calls `_handle_idle_timeout()`, which closes the connection only if `_idle` is true (between requests). The `_idle` flag acts as a safety net: if the timer fires during a long computation (no TCP activity but a request is pending), `_idle` is false and the connection stays open.

**Flow-controlled streaming**: `send_chunk()` returns a `ChunkSendToken` immediately. The chunk data and token flow through the response queue (buffered or flushed directly depending on head-of-line position and throttle state). On flush, `_flush_data(data, token)` calls `TCPConnection.send()` and pushes the HTTP-level token onto a FIFO (`_pending_sent_tokens`) inside `HTTPServer`. When lori's `_on_sent` fires asynchronously (data handed to OS), `HTTPServer._handle_sent()` pops the FIFO — if the token is a `ChunkSendToken`, it delivers `on_chunk_sent(token)` to the actor; if `None` (internal send: headers, terminal chunk, error response), it skips. The FIFO ordering depends on lori's guarantee that `_on_sent` callbacks arrive in the same order as the `send()` calls that produced them. The FIFO is cleared on connection close (`_close_connection()` and `_handle_closed()`) — any `_on_send_failed` callbacks that arrive afterward find the `_Closed` state and no-op.

### Implementation plan

See [Discussion #2](https://github.com/ponylang/stallion/discussions/2) for the phased implementation plan.

## Release Notes

Follow the standard ponylang release notes conventions. Create individual `.md` files in `.release-notes/` for each PR with user-facing changes.

## File Layout

- `stallion/` — main package source
  - `method.pony` — HTTP method types (`Method` interface, 9 primitives, `Methods` parse/enumerate)
  - `version.pony` — HTTP version types (`HTTP10`, `HTTP11`, `Version` closed union)
  - `status.pony` — HTTP status codes (`Status` interface, 35 standard primitives)
  - `headers.pony` — Case-insensitive header collection (`Headers` class)
  - `_response_serializer.pony` — Response wire-format serializer (package-private)
  - `_mort.pony` — Runtime enforcement primitives (`_IllegalState`, `_Unreachable`)
  - `parse_error.pony` — Parse error types (`ParseError` union, 8 error primitives)
  - `_parser_config.pony` — Parser size limit configuration
  - `_request_parser_notify.pony` — Parser callback trait (synchronous `ref` methods)
  - `_parser_state.pony` — Parser state machine (state interface, 6 state classes, `_BufferScan`)
  - `_request_parser.pony` — Request parser class (entry point, buffer management)
  - `request.pony` — Immutable request metadata bundle (`Request val`: method, URI, version, headers)
  - `chunk_send_token.pony` — Opaque chunk send token (`ChunkSendToken val`, `Equatable`, private constructor)
  - `http_server_lifecycle_event_receiver.pony` — HTTP callback trait (`HTTPServerLifecycleEventReceiver`: on_request, on_body_chunk, on_request_complete, on_chunk_sent, on_closed, on_throttled, on_unthrottled)
  - `http_server_actor.pony` — Server actor trait (`HTTPServerActor`: extends `TCPConnectionActor` and `HTTPServerLifecycleEventReceiver`, provides `_connection()` default)
  - `stallion.pony` — Package docstring
  - `http_server.pony` — Protocol class (`HTTPServer`: owns TCP connection + parser + URI parsing + response queue, implements `ServerLifecycleEventReceiver` + `_RequestParserNotify` + `_ResponseQueueNotify`)
  - `_keep_alive_decision.pony` — Keep-alive logic (`_KeepAliveDecision` primitive)
  - `response_builder.pony` — Pre-serialized response construction (`ResponseBuilder` primitive, `ResponseHeadersBuilder`/`ResponseBodyBuilder` phase interfaces, `_ResponseBuilderImpl`)
  - `start_chunked_response_result.pony` — Typed result from `start_chunked_response()` (`StartChunkedResponseResult` union, `StreamingStarted`/`AlreadyResponded`/`ChunkedNotSupported` primitives)
  - `responder.pony` — Per-request response sender (`Responder` class, state machine, complete and streaming modes)
  - `_response_queue.pony` — Pipelined response ordering (`_ResponseQueue`, `_ResponseQueueNotify`, `_QueueEntry`)
  - `_chunked_encoder.pony` — Chunked transfer encoding (`_ChunkedEncoder` primitive)
  - `server_config.pony` — Server configuration (`ServerConfig` class, `DefaultIdleTimeout` primitive)
  - `_error_response.pony` — Pre-built error response strings (`_ErrorResponse` primitive)
  - `_connection_state.pony` — Connection lifecycle states (`_Active`, `_Closed`; routes `on_sent` for chunk token delivery)
- `assets/` — test assets
  - `cert.pem` — Self-signed test certificate for SSL examples
  - `key.pem` — Test private key for SSL examples
- `examples/` — example programs
  - `hello/main.pony` — Greeting server with URI parsing and query parameter extraction
  - `ssl/main.pony` — HTTPS server using SSL/TLS
  - `streaming/main.pony` — Flow-controlled chunked transfer encoding streaming response using `on_chunk_sent()` callbacks
