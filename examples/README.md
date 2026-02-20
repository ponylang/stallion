# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the http_server library. Ordered from simplest to most involved.

## [hello](hello/)

Greeting server that responds with "Hello, World!" by default, or "Hello, {name}!" when a `?name=X` query parameter is provided. Demonstrates the core API: a listener actor implements `lori.TCPListenerActor`, creates connection actors in `_on_accept`, and each connection actor uses `HTTPServerActor`, `HTTPServer`, `Request`, `Responder`, `ResponseBuilder`, and `ServerConfig`. Start here if you're new to the library.

## [builder](builder/)

Constructs responses dynamically using `ResponseBuilder`. Demonstrates the builder's typed state machine that guides the caller through status line, headers, then body. Similar to hello but focused on the response construction API.

## [ssl](ssl/)

HTTPS server using SSL/TLS. Demonstrates creating an `SSLContext`, loading certificate and key files, and passing the context to connection actors via `_on_accept`. The `HTTPServer` handles SSL dispatch internally — the actor code is identical for HTTP and HTTPS.

## [streaming](streaming/)

Streams responses using chunked transfer encoding with timer-driven delivery. Demonstrates `start_chunked_response()`, `send_chunk()`, and `finish_response()` on `Responder`. The actor stores the `Responder` and sends chunks at one-second intervals as timer messages arrive, simulating a response where data becomes available over time.
