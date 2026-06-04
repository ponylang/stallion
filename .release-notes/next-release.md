## Reject malformed and unsupported Transfer-Encoding values

Previously, Stallion decided whether a request body was chunked by checking if the `Transfer-Encoding` header value contained the substring `chunked` anywhere. A value like `x-chunked-fake` matched, with two bad outcomes: a request with such a header and no body left the connection open forever with no response, and a request that did supply a chunked-shaped body was accepted as if its (unknown) transfer coding were understood.

Stallion now treats `Transfer-Encoding` as the comma-separated list of transfer codings it actually is, matching `chunked` exactly and case-insensitively. The only supported coding is `chunked`, and it must be the final coding. A value naming a coding Stallion does not implement (for example `gzip` or `x-chunked-fake`) is answered with `501 Not Implemented`. A value that cannot frame the message — empty, `chunked` listed more than once, or `chunked` applied before another coding — is answered with `400 Bad Request`. In both cases the connection is closed instead of hanging.

## Fix Connection: close handling

Stallion recognized a `Connection: close` (or `keep-alive`) directive only when it was the sole value on a single `Connection` header line. A `close` token alongside other options — `Connection: close, x-fake-option` or `Connection: keep-alive, close` — was ignored, as was a `close` sent on a second `Connection` line, so the connection stayed open instead of closing after the response. Browsers and proxies routinely send multi-token Connection values such as `keep-alive, Upgrade` or `close, TE`, so this affected ordinary traffic, not just unusual requests.

Stallion now reads `Connection` as the comma-separated list it is and honors a `close` token wherever it appears — anywhere in the list, in any case, and across repeated `Connection` header lines. A `close` token always closes the connection, taking precedence over `keep-alive`.

As part of this, `Headers.get` now combines repeated lines of a comma-separated list header — such as `Connection`, `Accept`, or `Cache-Control` — into one value, joined by commas in the order the lines appeared, matching how those fields are defined. Headers that are not comma-separated lists, such as `Set-Cookie`, are unaffected and still return their first value.

## Fix parsing of quoted parameter values in Transfer-Encoding and Accept headers

Fixed several bugs in how quoted parameter values are parsed in `Transfer-Encoding` and `Accept` header fields.

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

