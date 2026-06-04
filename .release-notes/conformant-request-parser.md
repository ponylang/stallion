## Reject HTTP request smuggling vectors and tighten request conformance

Stallion's HTTP/1.1 request parser previously accepted a range of malformed requests that are recognized request-smuggling vectors. When Stallion sits behind or in front of another HTTP processor that disagrees about where one request ends and the next begins, an attacker can use these to slip a hidden request past one of them. The parser now rejects them and closes the connection.

A request is now rejected when it contains any of:

- both a `Content-Length` and a `Transfer-Encoding` header field
- a bare CR or bare LF where a CRLF is required (the request line, a header or trailer field, or chunk framing)
- a NUL byte in a header or trailer field value
- a field name that is not a valid token, or whitespace between the field name and its colon
- an obsolete line-folded header
- a malformed chunk size or an invalid chunk extension
- a `Transfer-Encoding` that is not a single, final `chunked` coding
- a framing, routing, or control field (such as `Transfer-Encoding`, `Content-Length`, or `Host`) in the trailer section

Trailer fields are now held to the same standard as header fields.

The parser is also stricter about request conformance. An HTTP/1.1 request must carry exactly one `Host` header field: a request missing `Host`, or carrying more than one `Host` line (on any HTTP version), is rejected with `400 Bad Request`. A request whose method is well-formed but not one Stallion implements now receives `501 Not Implemented` instead of `400 Bad Request`.
