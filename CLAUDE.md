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

Package: `http_server` (repo name is `lori_http_server`, but the Pony package name is `http_server`)

Built on lori (v0.8.3). Lori provides raw TCP I/O with a connection-actor model: `_on_received(data: Array[U8] iso)` for incoming data, `TCPConnection.send(data): (SendToken | SendError)` for outgoing, plus backpressure notifications and SSL support.

### Key design decisions

**Protocol class pattern (mirrors lori's layering)**: The user's actor IS the connection — no hidden internal actor. The architecture mirrors lori's own layering:

```
lori layer:    TCPConnection (class) + TCPConnectionActor (trait) + ServerLifecycleEventReceiver (trait)
http layer:    HTTPServer (class) + HTTPServerActor (trait) + HTTPServerLifecycleEventReceiver (trait)
```

The user's actor stores `HTTPServer` as a field and implements `HTTPServerActor` (which extends both `TCPConnectionActor` and `HTTPServerLifecycleEventReceiver`). The protocol class handles all HTTP parsing, response queue management, and connection lifecycle — calling back to the user's actor for HTTP-level events. Other actors can communicate directly with the user's actor since it IS the connection actor.

**No HTTP-layer listener wrapper**: A separate listener actor implements `lori.TCPListenerActor` directly, creating `HTTPServerActor` instances in `_on_accept`. Lifecycle callbacks (`_on_listening`, `_on_listen_failure`, `_on_closed`) go directly to the listener actor. This mirrors lori's own echo server pattern — `Main` creates the listener, the listener creates connections. No factory class, no notify class, no hidden internal actor.

**`none()` constructor for field defaults**: `HTTPServer.none()` creates a placeholder instance that allows the `_http` field to have a default value. This is needed because Pony actor constructors require all fields to be initialized before `this` becomes `ref`. Without a default, `this` is `tag` in the constructor body, which can't be passed to `HTTPServer.create()`. The `none()` instance is immediately replaced by `create()` — its methods are never called.

**Capability chain in the protocol constructor**: `HTTPServer.create` takes `server_actor: HTTPServerActor ref` (the user's `this`):
- Stored as `_lifecycle_event_receiver: (HTTPServerLifecycleEventReceiver ref | None)` — for synchronous HTTP callbacks (upcast; `None` for the `none()` placeholder)
- Stored as `_enclosing: (HTTPServerActor | None)` — for idle timer behavior (`ref <: tag`; `None` for the `none()` placeholder)
- Passed to `TCPConnection.server(auth, fd, server_actor, this)` as `TCPConnectionActor ref` — lori ASIO wiring (upcast)
- Protocol passes `this` to `TCPConnection.server()` as `ServerLifecycleEventReceiver ref`

**Parser callback is `ref`, not `tag`**: The parser runs inside the connection actor, so its callback interface uses `fun ref` methods (synchronous calls), not `be` behaviors (actor messages). This avoids the extra actor hop that `ponylang/http_server` requires.

**Trait-based state machines**: State machines (parser and connection lifecycle) follow the pattern from `ponylang/postgres`: states are classes implementing trait hierarchies. Traits for state categories supply default implementations that trap on invalid operations. Each state class owns its per-state data (buffers, accumulators), which is automatically cleaned up on state transitions. Invalid operations are enforced at runtime through trait defaults. The interface width should be adapted to each use case — HTTP needs narrower interfaces than postgres's ~40-method `_SessionState`.

**Relationship to `ponylang/http_server`**: That project is built on the stdlib `net` package and has actor-interaction issues we want to avoid. We may borrow internal logic (e.g., parsing techniques) but the overall architecture and actor interactions are designed fresh around lori's model.

**Connection lifecycle**: Connections are persistent by default (HTTP/1.1 keep-alive). The user's listener creates connections via `_on_accept`, passing `ServerConfig` for parser limits and idle timeout:

```pony
let config = ServerConfig("localhost", "8080" where idle_timeout' = 60)
```

For HTTPS, pass an `SSLContext val` (from `ssl/net`) to connection actors:

```pony
fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
  MyServer(_server_auth, fd, _config, _ssl_ctx, _timers)
```

SSL handshake, encryption, and decryption are handled transparently by lori — actors see no difference between HTTP and HTTPS connections. `HTTPServer.create` handles SSL dispatch internally (single constructor takes `(SSLContext val | None)`).

Connections close when the client sends `Connection: close`, on HTTP/1.0 requests without `Connection: keep-alive`, after a parse error (with the appropriate error status code), or when the idle timeout expires. Backpressure from lori is propagated to the actor via `throttled()`/`unthrottled()` callbacks and to the response queue via `throttle()`/`unthrottle()`.

**URI parsing in the protocol layer**: The protocol layer parses the raw request-target string into a `URI val` (from the `uri` package, `ponylang/uri`) before delivering it to the actor as part of the `Request val` object. For CONNECT requests, `ParseURIAuthority` parses the authority-form target; for all other methods, `ParseURI` handles origin-form, absolute-form, and asterisk-form targets. Invalid URIs are rejected with 400 Bad Request before reaching the actor. Actors that access URI components (e.g., `request'.uri.query_params()`) need `use "uri"` in their package to name types like `QueryParams`.

**Streaming-only body delivery**: Body data is delivered incrementally via `body_chunk()` callbacks on `HTTPServerLifecycleEventReceiver`. Actors that need the complete body accumulate chunks manually. There is no built-in buffering adapter — convenience buffered body delivery is future work per [lori #7](https://github.com/ponylang/lori/issues/7).

**Per-request Responder and response queue**: Each request gets its own `Responder` instance, delivered via `HTTPServerLifecycleEventReceiver.request_complete()`. The user's listener creates a new actor per connection in `_on_accept`. Responders send data through a `_ResponseQueue` that ensures pipelined responses are delivered in request order, regardless of the order actors respond. The queue calls back to the protocol via `_ResponseQueueNotify` for TCP I/O — it never holds the TCP connection directly. Responders support two modes: complete (`respond()` with pre-serialized bytes from `ResponseBuilder`) and streaming (`start_chunked_response()` + `send_chunk()` + `finish_response()` using chunked transfer encoding). After connection close, any Responders the actor still holds become inert — their methods route to the closed queue, which no-ops everything.

**Response builder**: `ResponseBuilder` constructs complete HTTP responses as pre-serialized `Array[U8] val` byte arrays, using a typed state machine (via return-type narrowing) to enforce correct construction order: status line, then headers, then body. The builder output is suitable for caching and reuse via `Responder.respond()`, avoiding per-request serialization overhead. The caller is responsible for all response formatting including Content-Length — no headers are injected automatically.

**Idle timer flow**: Timer fires -> `_IdleTimerNotify` (in Timers actor) sends `be _idle_timeout()` to user's actor (via tag) -> `HTTPServerActor._idle_timeout()` default impl forwards to `_http_connection()._handle_idle_timeout()`.

### Implementation plan

See [Discussion #2](https://github.com/ponylang/lori_http_server/discussions/2) for the phased implementation plan.

## Release Notes

No release notes until after the first release. This project is pre-1.0 and hasn't been released yet — there are no users to notify of changes.

## File Layout

- `http_server/` — main package source
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
  - `http_server_lifecycle_event_receiver.pony` — HTTP callback trait (`HTTPServerLifecycleEventReceiver`: request, body_chunk, request_complete, closed, throttled, unthrottled)
  - `http_server_actor.pony` — Server actor trait (`HTTPServerActor`: extends `TCPConnectionActor` and `HTTPServerLifecycleEventReceiver`, provides `_connection()` and `_idle_timeout()` defaults)
  - `http_server_protocol.pony` — Protocol class (`HTTPServer`: owns TCP connection + parser + URI parsing + response queue + idle timer, implements `ServerLifecycleEventReceiver` + `_RequestParserNotify` + `_ResponseQueueNotify`; also contains `_KeepAliveDecision` and `_IdleTimerNotify`)
  - `response_builder.pony` — Pre-serialized response construction (`ResponseBuilder` primitive, `ResponseBuilderHeaders`/`ResponseBuilderBody` phase interfaces, `_ResponseBuilderImpl`)
  - `responder.pony` — Per-request response sender (`Responder` class, state machine, complete and streaming modes)
  - `_response_queue.pony` — Pipelined response ordering (`_ResponseQueue`, `_ResponseQueueNotify`, `_QueueEntry`)
  - `_chunked_encoder.pony` — Chunked transfer encoding (`_ChunkedEncoder` primitive)
  - `server_config.pony` — Server configuration (`ServerConfig` class)
  - `_error_response.pony` — Pre-built error response strings (`_ErrorResponse` primitive)
  - `_connection_state.pony` — Connection lifecycle states (`_Active`, `_Closed`)
- `assets/` — test assets
  - `cert.pem` — Self-signed test certificate for SSL examples
  - `key.pem` — Test private key for SSL examples
- `examples/` — example programs
  - `hello/main.pony` — Greeting server with URI parsing and query parameter extraction
  - `builder/main.pony` — Dynamic response construction using `ResponseBuilder` and `respond()`
  - `ssl/main.pony` — HTTPS server using SSL/TLS
  - `streaming/main.pony` — Timer-driven chunked transfer encoding streaming response
