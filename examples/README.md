# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the http_server library. Ordered from simplest to most involved.

## [hello](hello/)

Greeting server that responds with "Hello, World!" by default, or "Hello, {name}!" when a `?name=X` query parameter is provided. Demonstrates the core API: a listener actor implements `lori.TCPListenerActor`, creates connection actors in `_on_accept`, and each connection actor uses `HTTPServerActor`, `HTTPServer`, `Request`, `Responder`, `ResponseBuilder`, and `ServerConfig`. Start here if you're new to the library.

## [ssl](ssl/)

HTTPS server using SSL/TLS. Demonstrates creating an `SSLContext`, loading certificate and key files, and passing the context to connection actors via `_on_accept`. Actors use `HTTPServer.ssl` instead of `HTTPServer` to create an HTTPS connection.

## [streaming](streaming/)

Streams responses using chunked transfer encoding with flow-controlled delivery driven by `on_chunk_sent()` callbacks. Demonstrates `start_chunked_response()`, `send_chunk()`, `finish_response()`, and `on_chunk_sent()` on `Responder` and `HTTPServerLifecycleEventReceiver`. The actor sends the first chunk in `on_request()`, then each `on_chunk_sent()` callback triggers the next chunk — natural backpressure without timers or manual windowing.
