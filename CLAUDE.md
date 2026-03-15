# HTTP Server for Pony

## Building

```
make ssl=3.0.x      # build and run tests (OpenSSL 3.x)
make ssl=1.1.x      # build and run tests (OpenSSL 1.1.x)
make test-one t=TestName ssl=3.0.x  # run a single test by name
make ssl=libressl   # build and run tests (LibreSSL)
make clean           # clean build artifacts
```

The `ssl` option is required because this library and lori depend on the `ssl` package.

## Architecture

Package: `stallion` (repo name is `stallion`, Pony package name is `stallion`)

Built on lori (v0.10.0). Lori provides raw TCP I/O with a connection-actor model: `_on_received(data: Array[U8] iso)` for incoming data, `TCPConnection.send(data): (SendToken | SendError)` for outgoing, plus backpressure notifications, SSL support, and per-connection ASIO-level idle timers.

### Key design decisions

**Protocol class pattern (mirrors lori's layering)**: The user's actor IS the connection — no hidden internal actor. The architecture mirrors lori's own layering:

```
lori layer:    TCPConnection (class) + TCPConnectionActor (trait) + ServerLifecycleEventReceiver (trait)
http layer:    HTTPServer (class) + HTTPServerActor (trait) + HTTPServerLifecycleEventReceiver (trait)
```

The user's actor stores `HTTPServer` as a field and implements `HTTPServerActor` (which extends both `TCPConnectionActor` and `HTTPServerLifecycleEventReceiver`). The protocol class handles all HTTP parsing, response queue management, and connection lifecycle — calling back to the user's actor for HTTP-level events. Other actors can communicate directly with the user's actor since it IS the connection actor.

**No HTTP-layer listener wrapper**: A separate listener actor implements `lori.TCPListenerActor` directly, creating `HTTPServerActor` instances in `_on_accept`. Lifecycle callbacks (`_on_listening`, `_on_listen_failure`, `_on_closed`) go directly to the listener actor. No factory class, no notify class, no hidden internal actor.

**`none()` constructor for field defaults**: `HTTPServer.none()` creates a placeholder instance that allows the `_http` field to have a default value. This is needed because Pony actor constructors require all fields to be initialized before `this` becomes `ref`. Without a default, `this` is `tag` in the constructor body, which can't be passed to `HTTPServer.create()`. The `none()` instance is immediately replaced by `create()` or `ssl()` — its methods are never called.

**Parser callback is `ref`, not `tag`**: The parser runs inside the connection actor, so its callback interface uses `fun ref` methods (synchronous calls), not `be` behaviors (actor messages).

**Trait-based state machines**: State machines (parser and connection lifecycle) follow the pattern from `ponylang/postgres`: states are classes implementing trait hierarchies. Traits for state categories supply default implementations that trap on invalid operations. Each state class owns its per-state data (buffers, accumulators), which is automatically cleaned up on state transitions.

**Connection lifecycle**: Connections are persistent by default (HTTP/1.1 keep-alive). The user's listener creates connections via `_on_accept`, passing `ServerConfig` for parser limits and idle timeout. For HTTPS, actors use `HTTPServer.ssl` instead of `HTTPServer`, passing an `SSLContext val`. Connections close on `Connection: close`, HTTP/1.0 without keep-alive, parse errors, idle timeout, `max_requests_per_connection` limit, or when the actor calls `HTTPServer.close()`. `HTTPServer.yield_read()` cooperatively yields the read loop for scheduler fairness — call it from HTTP callbacks to implement yield policies. Backpressure from lori is propagated via `on_throttled()`/`on_unthrottled()` callbacks.

**URI parsing**: The protocol layer parses request-target strings into `URI val` (from `ponylang/uri`) before delivering them in the `Request val` object. Invalid URIs are rejected with 400 Bad Request. Actors that access URI components (e.g., `request'.uri.query_params()`) need `use "uri"` in their package to name types like `QueryParams`.

**Streaming-only body delivery**: Body data is delivered incrementally via `on_body_chunk()` callbacks. Actors that need the complete body accumulate chunks manually.

**Per-request Responder**: Each request gets its own `Responder` instance, delivered to both `on_request()` and `on_request_complete()`. Simple servers override only `on_request_complete(request', responder)`. Override `on_request()` when you need to respond before the body arrives (e.g., 413 rejection, starting a streaming response). Responders support two modes: complete (`respond()` with pre-serialized bytes from `ResponseBuilder`) and streaming (`start_chunked_response()` + `send_chunk()` + `finish_response()`). A `_ResponseQueue` ensures pipelined responses are delivered in request order. After connection close, any Responders the actor still holds become inert.

## Release Notes

Follow the standard ponylang release notes conventions. Create individual `.md` files in `.release-notes/` for each PR with user-facing changes.

## File Layout

- `stallion/` — main package source
  - `method.pony` — HTTP method types (`Method` interface, 9 primitives, `Methods` parse/enumerate)
  - `version.pony` — HTTP version types (`HTTP10`, `HTTP11`, `Version` closed union)
  - `status.pony` — HTTP status codes (`Status` interface, 35 standard primitives)
  - `header.pony` — Single HTTP header name-value pair (`Header val` class)
  - `headers.pony` — Case-insensitive header collection (`Headers` class, stores `Array[Header val]`)
  - `_response_serializer.pony` — Response wire-format serializer (package-private)
  - `_mort.pony` — Runtime enforcement primitives (`_IllegalState`, `_Unreachable`)
  - `parse_error.pony` — Parse error types (`ParseError` union, 8 error primitives)
  - `_parser_config.pony` — Parser size limit configuration
  - `_request_parser_notify.pony` — Parser callback trait (synchronous `ref` methods)
  - `_parser_state.pony` — Parser state machine (state interface, 6 state classes, `_BufferScan`)
  - `_request_parser.pony` — Request parser class (entry point, buffer management)
  - `request.pony` — Immutable request metadata bundle (`Request val`: method, URI, version, headers, cookies)
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
  - `max_requests_per_connection.pony` — Constrained type for max requests limit (`MaxRequestsPerConnection`, `MakeMaxRequestsPerConnection`, validator)
  - `server_config.pony` — Server configuration (`ServerConfig` class with `max_requests_per_connection: (MaxRequestsPerConnection | None)`, `DefaultIdleTimeout` primitive)
  - `_error_response.pony` — Pre-built error response strings (`_ErrorResponse` primitive)
  - `_connection_state.pony` — Connection lifecycle states (`_Active`, `_Closed`; routes `on_sent` for chunk token delivery)
  - `request_cookie.pony` — Single parsed cookie name-value pair (`RequestCookie val`, private constructor)
  - `request_cookies.pony` — Immutable collection of parsed request cookies (`RequestCookies val`, `get()`, `values()`, `size()`)
  - `parse_cookies.pony` — Cookie parser (`ParseCookies` primitive: `from_headers()`, `apply()`, lenient RFC 6265 §5.4 parsing)
  - `same_site.pony` — SameSite attribute types (`SameSiteStrict`, `SameSiteLax`, `SameSiteNone`, `SameSite` union)
  - `set_cookie_build_error.pony` — Build error types (`InvalidCookieName`, `InvalidCookieValue`, `InvalidCookiePath`, `InvalidCookieDomain`, `CookiePrefixViolation`, `SameSiteRequiresSecure`, `SetCookieBuildError` union)
  - `set_cookie.pony` — Validated, pre-serialized `Set-Cookie` header (`SetCookie val`, `header_value()`, private constructor)
  - `set_cookie_builder.pony` — `Set-Cookie` header builder (`SetCookieBuilder ref`, secure defaults, chaining, prefix rules)
  - `_cookie_validator.pony` — Cookie name/value/attribute validation (RFC 2616 token, RFC 6265 cookie-octet, path/domain safety)
  - `_http_date.pony` — IMF-fixdate formatter for `Expires` attribute (`_HTTPDate` primitive)
- `assets/` — test assets
  - `cert.pem` — Self-signed test certificate for SSL examples
  - `key.pem` — Test private key for SSL examples
- `examples/` — example programs
  - `cookies/main.pony` — Visit counter demonstrating `Request.cookies` and `SetCookieBuilder`
  - `hello/main.pony` — Greeting server with URI parsing and query parameter extraction
  - `ssl/main.pony` — HTTPS server using SSL/TLS
  - `streaming/main.pony` — Flow-controlled chunked transfer encoding streaming response using `on_chunk_sent()` callbacks
  - `yield/main.pony` — Scheduler fairness via `HTTPServer.yield_read()` with a request-count-based yield policy
