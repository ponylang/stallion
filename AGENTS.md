# HTTP Server for Pony

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

## Building

```
make ssl=3.0.x      # build and run tests (OpenSSL 3.x)
make ssl=1.1.x      # build and run tests (OpenSSL 1.1.x)
make test-one t=TestName ssl=3.0.x  # run a single test by name
make ssl=libressl   # build and run tests (LibreSSL)
make clean           # clean build artifacts
```

The `ssl` option is required because this library and lori depend on the `ssl` package.

## RFC conformance

Stallion conforms to the HTTP RFCs. We reject what the RFCs say to reject and accept what they say to accept — and we stop there. We do not add non-conformant behavior to compensate for an intermediary that mishandles a conformant message.

A proxy that normalizes a message in a way the spec forbids — mapping `_` to `-` in a field name, trimming whitespace a recipient is required to reject, splitting on a bare LF — can desynchronize from us. That is the intermediary's bug, and it is outside our control. It is not a reason for us to deviate from the spec, because the deviation would break conformant clients to chase a misbehaving party we cannot fix.

This is why our request-smuggling defenses go exactly as far as the RFCs do and no further. We reject `Content-Length` together with `Transfer-Encoding` (RFC 9112 §6.3) and reject a field name that is not a valid token (RFC 9110 §5.6.2, RFC 9112 §5.1) because the RFCs say to. We do *not* reject a field name like `X_Custom` to defend against an upstream that might rewrite the underscore — the underscore is a valid token character, so we accept it.

## Architecture

Package: `stallion` (repo name is `stallion`, Pony package name is `stallion`)

Built on lori (v0.15.0). Lori provides raw TCP I/O with a connection-actor model: `_on_received(data: Array[U8] iso)` for incoming data, `TCPConnection.send(data): (SendToken | SendError)` for outgoing, plus backpressure notifications, SSL support, per-connection ASIO-level idle timers, and general-purpose one-shot timers.

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

**Connection lifecycle**: Connections are persistent by default (HTTP/1.1 keep-alive). The user's listener creates connections via `_on_accept`, passing `ServerConfig` for parser limits and idle timeout. For HTTPS, actors use `HTTPServer.ssl` instead of `HTTPServer`, passing an `SSLContext val`. Connections that fail before starting (e.g., SSL handshake failure) fire `on_start_failure(reason)` — neither `on_request()` nor `on_closed()` fires for these connections. Active connections close on `Connection: close`, HTTP/1.0 without keep-alive, parse errors, idle timeout, `max_requests_per_connection` limit, or when the actor calls `HTTPServer.close()`. `HTTPServer.yield_read()` cooperatively yields the read loop for scheduler fairness — call it from HTTP callbacks to implement yield policies. Backpressure from lori is propagated via `on_throttled()`/`on_unthrottled()` callbacks.

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
  - `headers.pony` — Case-insensitive header collection (`Headers` class, stores `Array[Header val]`; `get()` combines repeated list-valued field lines per RFC 9110 §5.3)
  - `_list_valued_headers.pony` — Allowlist of comma-separated list header fields and documented deny list (`_ListValuedHeaders` primitive)
  - `_response_serializer.pony` — Response wire-format serializer (package-private)
  - `_mort.pony` — Runtime enforcement primitives (`_IllegalState`, `_Unreachable`)
  - `_ows.pony` — RFC 9110 §5.6.3 optional whitespace (SP/HTAB) — single source for the OWS predicate, zero-copy trim, and strip charset (`_OWS` primitive)
  - `_token.pony` — RFC 9110 §5.6.2 token (`tchar`) — single source for the token-character predicate and whole-string validity (`_Token` primitive); used to validate HTTP field names (RFC 9112 §5.1) and cookie names
  - `_quoted_split.pony` — RFC 9110 §5.6.4 quoted-string-aware delimiter split (`_QuotedSplit` primitive) — shared by the Transfer-Encoding and Accept parsers so a delimiter inside a quoted parameter value (including `quoted-pair` escapes) does not split an element; returns `(segments, unterminated)` so the framing path can reject a malformed (unterminated-quote) value while Accept ignores it
  - `parse_error.pony` — Parse error types (`ParseError` union, 11 error primitives)
  - `_parser_config.pony` — Parser size limit configuration
  - `_request_parser_notify.pony` — Parser callback trait (synchronous `ref` methods)
  - `_transfer_encoding.pony` — Transfer-Encoding tokenizer and RFC 9112 §6.1/§6.3 coding decision (`_TransferEncoding` primitive, `_ChunkedFraming` sentinel)
  - `_parser_state.pony` — Parser state machine (state interface, 6 state classes, `_BufferScan`)
  - `_request_parser.pony` — Request parser class (entry point, buffer management)
  - `request.pony` — Immutable request metadata bundle (`Request val`: method, URI, version, headers, cookies)
  - `chunk_send_token.pony` — Opaque chunk send token (`ChunkSendToken val`, `Equatable`, private constructor)
  - `http_server_lifecycle_event_receiver.pony` — HTTP callback trait (`HTTPServerLifecycleEventReceiver`: on_request, on_body_chunk, on_request_complete, on_closed, on_start_failure, on_throttled, on_chunk_sent, on_unthrottled, on_timer, on_timer_failure)
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
  - `_connection_state.pony` — Connection lifecycle states (`_Active`, `_Closed`; dispatches lori events to server handler methods)
  - `request_cookie.pony` — Single parsed cookie name-value pair (`RequestCookie val`, private constructor)
  - `request_cookies.pony` — Immutable collection of parsed request cookies (`RequestCookies val`, `get()`, `values()`, `size()`)
  - `parse_cookies.pony` — Cookie parser (`ParseCookies` primitive: `from_headers()`, `apply()`, lenient RFC 6265 §5.4 parsing)
  - `same_site.pony` — SameSite attribute types (`SameSiteStrict`, `SameSiteLax`, `SameSiteNone`, `SameSite` union)
  - `set_cookie_build_error.pony` — Build error types (`InvalidCookieName`, `InvalidCookieValue`, `InvalidCookiePath`, `InvalidCookieDomain`, `CookiePrefixViolation`, `SameSiteRequiresSecure`, `SetCookieBuildError` union)
  - `set_cookie.pony` — Validated, pre-serialized `Set-Cookie` header (`SetCookie val`, `header_value()`, private constructor)
  - `set_cookie_builder.pony` — `Set-Cookie` header builder (`SetCookieBuilder ref`, secure defaults, chaining, prefix rules)
  - `_cookie_validator.pony` — Cookie name/value/attribute validation (cookie names via `_Token`, RFC 6265 cookie-octet, path/domain safety)
  - `_http_date.pony` — IMF-fixdate formatter for `Expires` attribute (`_HTTPDate` primitive)
  - `media_type.pony` — HTTP media type (`MediaType val` class, `Equatable & Stringable`)
  - `no_acceptable_type.pony` — Content negotiation failure (`NoAcceptableType` primitive)
  - `content_negotiation_result.pony` — Result type alias (`MediaType val | NoAcceptableType`)
  - `_quality.pony` — Constrained quality factor 0–1000 (`_Quality`, `_MakeQuality`, `_QualityValidator`)
  - `_accept_range.pony` — Parsed Accept header media range (`_AcceptRange val`, specificity scoring)
  - `_accept_parser.pony` — Accept header parser (`_AcceptParser` primitive, lenient, quoted-string-aware)
  - `content_negotiation.pony` — Content negotiation (`ContentNegotiation` primitive: `from_request()`, `apply()`, RFC 7231 §5.3.2)
- `assets/` — test assets
  - `cert.pem` — Self-signed test certificate for SSL examples
  - `key.pem` — Test private key for SSL examples
- `examples/` — example programs
  - `cookies/main.pony` — Visit counter demonstrating `Request.cookies` and `SetCookieBuilder`
  - `hello/main.pony` — Greeting server with URI parsing and query parameter extraction
  - `negotiate/main.pony` — Content negotiation server responding with JSON or plain text based on Accept header
  - `ssl/main.pony` — HTTPS server using SSL/TLS
  - `request_timeout/main.pony` — Request processing deadline using `set_timer()`/`cancel_timer()`/`on_timer()`
  - `streaming/main.pony` — Flow-controlled chunked transfer encoding streaming response using `on_chunk_sent()` callbacks
  - `yield/main.pony` — Scheduler fairness via `HTTPServer.yield_read()` with a request-count-based yield policy
