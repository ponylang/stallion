"""
HTTPS server that responds to every request with "Hello, World!".

Demonstrates SSL/TLS support: creating an `SSLContext`, loading certificate
and key files, and passing the context to connection actors via `_on_accept`.
Actors use `HTTPServer.ssl` instead of `HTTPServer` to create an HTTPS
connection.

Must be run from the project root so the relative certificate paths resolve
correctly. Test with `curl -k https://localhost:8443/`.
"""
