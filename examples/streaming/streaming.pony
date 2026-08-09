"""
HTTP server that streams responses using chunked transfer encoding with
flow-controlled delivery driven by `on_chunk_sent()` callbacks.

Demonstrates the streaming response API: `start_chunked_response()`,
`send_chunk()`, `finish_response()`, and `on_chunk_sent()`. The actor sends
the first chunk in `on_request()`, then each `on_chunk_sent()` callback
drives the next chunk, so the OS has accepted each chunk before the next one
goes out — backpressure without timers or manual windowing.

A callback can go missing; see
`stallion.HTTPServerLifecycleEventReceiver.on_chunk_sent()` for when. This
actor stops sending when a callback goes missing, and because
`finish_response()` runs only from the fifth callback, a callback lost
before that leaves the response body unterminated.

Note: this demonstrates streaming *responses*, not streaming request
bodies. Request body data arrives via `on_body_chunk()` callbacks — this
example does not accumulate request body data.
"""
