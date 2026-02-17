# HTTP Server for Pony

## Building

```
make ssl=3.0.x      # build and run tests (OpenSSL 3.x)
make ssl=1.1.x      # build and run tests (OpenSSL 1.1.x)
make ssl=libressl   # build and run tests (LibreSSL)
make clean           # clean build artifacts
```

The `ssl` option is required because lori depends on the `ssl` package.

## Architecture

Package: `http_server` (repo name is `lori_http_server`, but the Pony package name is `http_server`)

Built on lori (v0.8.1). Lori provides raw TCP I/O with a connection-actor model: `_on_received(data: Array[U8] iso)` for incoming data, `TCPConnection.send(data): (SendToken | SendError)` for outgoing, plus backpressure notifications and SSL support.

### Key design decisions

**Single-actor connection model**: Unlike `ponylang/http_server` (which uses two actors per connection with message-passing between them), this library keeps everything in one actor per connection (`_Connection`): TCP I/O, parsing, handler dispatch, response queue, and response sending. The handler's `ref` methods run synchronously inside the connection actor. No unnecessary actor boundaries. The `Server` actor is a thin listener wrapper that creates `_Connection` actors on accept.

**Parser callback is `ref`, not `tag`**: The parser runs inside the connection actor, so its callback interface uses `fun ref` methods (synchronous calls), not `be` behaviors (actor messages). This avoids the extra actor hop that `ponylang/http_server` requires.

**Trait-based state machines**: State machines (parser and connection lifecycle) follow the pattern from `ponylang/postgres`: states are classes implementing trait hierarchies. Traits for state categories supply default implementations that trap on invalid operations. Each state class owns its per-state data (buffers, accumulators), which is automatically cleaned up on state transitions. Invalid operations are enforced at runtime through trait defaults. The interface width should be adapted to each use case — HTTP needs narrower interfaces than postgres's ~40-method `_SessionState`.

**Relationship to `ponylang/http_server`**: That project is built on the stdlib `net` package and has actor-interaction issues we want to avoid. We may borrow internal logic (e.g., parsing techniques) but the overall architecture and actor interactions are designed fresh around lori's model.

**Connection lifecycle**: Connections are persistent by default (HTTP/1.1 keep-alive). The `Server` constructor takes a `ServerConfig` for listen address, parser limits, connection limits, and idle timeout, plus an optional `ServerNotify` for lifecycle callbacks:

```pony
let config = ServerConfig("localhost", "8080" where idle_timeout' = 60)
Server(lori.TCPListenAuth(env.root), MyFactory, config, MyNotify)
```

Connections close when the client sends `Connection: close`, on HTTP/1.0 requests without `Connection: keep-alive`, after a parse error (with the appropriate error status code), or when the idle timeout expires. Backpressure from lori is propagated to the handler via `throttled()`/`unthrottled()` callbacks and to the response queue via `throttle()`/`unthrottle()`.

**URI parsing in the connection layer**: The connection layer parses the raw request-target string into a `URI val` (from the `http_server/uri` subpackage) before delivering it to the handler. For CONNECT requests, `ParseURIAuthority` parses the authority-form target; for all other methods, `ParseURI` handles origin-form, absolute-form, and asterisk-form targets. Invalid URIs are rejected with 400 Bad Request before reaching the handler. Handlers that override `request()` need `use "http_server/uri"` in their package to name the `URI` type.

**Per-request Responder and response queue**: Each request gets its own `Responder` instance, delivered via `Handler.request_complete(responder)`. The `HandlerFactory` no longer passes a `Responder` — it creates a bare handler. Responders send data through a `_ResponseQueue` that ensures pipelined responses are delivered in request order, regardless of the order handlers respond. The queue calls back to the connection via `_ResponseQueueNotify` for TCP I/O — it never holds the TCP connection directly. Responders support two modes: simple (`respond()` with full body) and streaming (`start_chunked_response()` + `send_chunk()` + `finish_response()` using chunked transfer encoding). After connection close, any Responders the handler still holds become inert — their methods route to the closed queue, which no-ops everything.

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
  - `handler.pony` — Application handler trait (`Handler`, receives `URI val`) and factory interface (`HandlerFactory`)
  - `responder.pony` — Per-request response sender (`Responder` class, state machine, simple and streaming modes)
  - `_response_queue.pony` — Pipelined response ordering (`_ResponseQueue`, `_ResponseQueueNotify`, `_QueueEntry`)
  - `_chunked_encoder.pony` — Chunked transfer encoding (`_ChunkedEncoder` primitive)
  - `server_config.pony` — Server configuration (`ServerConfig` class)
  - `server_notify.pony` — Server lifecycle notifications (`ServerNotify` interface)
  - `_error_response.pony` — Pre-built error response strings (`_ErrorResponse` primitive)
  - `_connection_state.pony` — Connection lifecycle states (`_Active`, `_Closed`)
  - `_connection.pony` — Per-connection actor (`_Connection`, owns TCP + parser + URI parsing + handler + response queue + idle timer)
  - `server.pony` — Listener actor (`Server`, accepts connections, creates `_Connection` actors)
  - `uri/` — URI parsing subpackage (RFC 3986)
    - `uri.pony` — Package docstring and `URI` class (`query_params()` convenience method)
    - `uri_authority.pony` — `URIAuthority` class
    - `percent_encoding.pony` — `PercentDecode`, `PercentEncode`, `URIPart` types, `InvalidPercentEncoding`
    - `parse_uri.pony` — `ParseURI` factory
    - `parse_uri_authority.pony` — `ParseURIAuthority` factory
    - `uri_parse_error.pony` — Error types and `URIParseError` union
    - `query_params.pony` — `QueryParams` class (key-based lookup for parsed query parameters)
    - `query_parameters.pony` — `ParseQueryParameters` primitive
    - `path_segments.pony` — `PathSegments` primitive
    - `_mort.pony` — `_Unreachable`, `_IllegalState` (package-private duplicate)
- `examples/` — example programs
  - `basic/main.pony` — Hello World HTTP server with URI parsing and query parameter extraction
  - `streaming/main.pony` — Chunked transfer encoding streaming response
