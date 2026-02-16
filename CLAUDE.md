# HTTP Server for Pony

## Building

```
make          # build and run tests
make test     # same as above
make clean    # clean build artifacts
```

## Architecture

Package: `http_server` (repo name is `lori_http_server`, but the Pony package name is `http_server`)

Built on lori (v0.8.1). Lori provides raw TCP I/O with a connection-actor model: `_on_received(data: Array[U8] iso)` for incoming data, `TCPConnection.send(data): (SendToken | SendError)` for outgoing, plus backpressure notifications and SSL support.

### Key design decisions

**Single-actor connection model**: Unlike `ponylang/http_server` (which uses two actors per connection with message-passing between them), this library keeps everything in one actor per connection: TCP I/O, parsing, handler dispatch, and response sending. The handler's `ref` methods run synchronously inside the connection actor. No unnecessary actor boundaries.

**Parser callback is `ref`, not `tag`**: The parser runs inside the connection actor, so its callback interface uses `fun ref` methods (synchronous calls), not `be` behaviors (actor messages). This avoids the extra actor hop that `ponylang/http_server` requires.

**Trait-based state machines**: State machines (parser and connection lifecycle) follow the pattern from `ponylang/postgres`: states are classes implementing trait hierarchies. Traits for state categories supply default implementations that trap on invalid operations. Each state class owns its per-state data (buffers, accumulators), which is automatically cleaned up on state transitions. Invalid operations are enforced at runtime through trait defaults. The interface width should be adapted to each use case — HTTP needs narrower interfaces than postgres's ~40-method `_SessionState`.

**Relationship to `ponylang/http_server`**: That project is built on the stdlib `net` package and has actor-interaction issues we want to avoid. We may borrow internal logic (e.g., parsing techniques) but the overall architecture and actor interactions are designed fresh around lori's model.

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
- `examples/` — example programs
