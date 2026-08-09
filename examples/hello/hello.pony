"""
Basic HTTP server that responds with a greeting. By default it responds
with "Hello, World!" but a `?name=X` query parameter customizes the
greeting (e.g., `?name=Pony` produces "Hello, Pony!").

Demonstrates the core API: a listener actor implements
`lori.TCPListenerActor` and creates `HTTPServerActor` instances in
`_on_accept`, plus query parameter extraction from the pre-parsed URI.

Body data arrives via `on_body_chunk()` callbacks. This example does not
accumulate request body data — for body accumulation, see the streaming
example.
"""
