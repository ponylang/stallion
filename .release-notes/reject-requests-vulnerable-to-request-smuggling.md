## Reject requests vulnerable to HTTP request smuggling

Stallion accepted two kinds of malformed request that are recognized HTTP request-smuggling vectors. When Stallion sits behind or in front of another HTTP intermediary that interprets the malformed request differently, the two can desynchronize about where one request ends and the next begins, letting a smuggled request slip past.

The first is a request carrying both a `Content-Length` and a `Transfer-Encoding` header. Stallion previously let the chunked framing win and processed the request; it now rejects any request carrying both headers, regardless of their values, per RFC 9112 §6.3.

The second is a request whose header field name is not a valid token — for example a name with whitespace before the colon (`Content-Length : 100`), whitespace inside the name (`Content -Length: 100`), or other characters RFC 9110 §5.6.2 does not permit. Stallion previously treated such a line as a header with an unusual, unrecognized name; it now requires every field name to be a valid token. This also satisfies RFC 9112 §5.1, which requires rejecting whitespace between a field name and its colon.

In both cases Stallion now responds with `400 Bad Request` and closes the connection.
