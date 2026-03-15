## Add content negotiation

Stallion now provides opt-in content negotiation for selecting a response content type based on the client's `Accept` header (RFC 7231 §5.3.2). This is useful for endpoints that support multiple formats — most endpoints serve a single content type and don't need this.

Use `ContentNegotiation.from_request()` to negotiate against a list of supported media types:

```pony
let supported = [as stallion.MediaType val:
  stallion.MediaType("application", "json")
  stallion.MediaType("text", "plain")
]
match stallion.ContentNegotiation.from_request(request', supported)
| let mt: stallion.MediaType val =>
  // Respond with the negotiated type (mt.string() gives "application/json" etc.)
| stallion.NoAcceptableType =>
  // Respond with 406 Not Acceptable
end
```

The algorithm follows RFC 7231 precedence rules: exact types beat wildcards, higher quality values win, ties go to the first type in the server's supported list, and `q=0` explicitly excludes a type. An absent `Accept` header means "accept anything" — the first supported type is returned.

`ContentNegotiation.apply()` accepts a raw Accept header value string directly, for testing or when you already have the header value.

New types: `MediaType`, `NoAcceptableType`, `ContentNegotiationResult`, `ContentNegotiation`.
