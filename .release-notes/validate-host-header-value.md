## Reject requests with a malformed Host header value

Stallion now rejects, with a 400 Bad Request, any request whose `Host` header value is not a well-formed host. A `Host` value must be a host name, IPv4 address, or bracketed IP-literal, optionally followed by a port in the range 0–65535.

Previously, only the presence and uniqueness of the `Host` field were checked — its value was accepted unconditionally. That let through values that are not valid hosts, such as `Host: a, b` (which is a single header line, so it passed the uniqueness check) or a port outside the valid range. These are now rejected, closing a request-routing ambiguity.
