## Add TCPBackend type parameter to HTTPServer and HTTPServerActor

`HTTPServer` and `HTTPServerActor` are now generic over a `lori.TCPBackend`, defaulting to `lori.RuntimeBackend`. Existing code that uses `HTTPServer` and `HTTPServerActor` without type arguments is unaffected — the default resolves to what shipped before.

The parameter is a testing hook: test code can substitute a fake backend to drive the connection state machine without real sockets. Production users should keep the default.
