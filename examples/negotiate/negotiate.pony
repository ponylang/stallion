"""
Content negotiation server that responds with JSON or plain text based on
the client's `Accept` header. Returns 406 Not Acceptable when the client
doesn't accept either format.

Demonstrates `ContentNegotiation.from_request()` for selecting a response
content type, and matching on `ContentNegotiationResult` to handle both
the matched type and the no-match case.

Try it:
  curl -H "Accept: application/json" http://localhost:8080/
  curl -H "Accept: text/plain" http://localhost:8080/
  curl -H "Accept: image/png" http://localhost:8080/
"""
