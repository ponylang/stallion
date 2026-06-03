## Reject malformed and unsupported Transfer-Encoding values

Previously, Stallion decided whether a request body was chunked by checking if the `Transfer-Encoding` header value contained the substring `chunked` anywhere. A value like `x-chunked-fake` matched, with two bad outcomes: a request with such a header and no body left the connection open forever with no response, and a request that did supply a chunked-shaped body was accepted as if its (unknown) transfer coding were understood.

Stallion now treats `Transfer-Encoding` as the comma-separated list of transfer codings it actually is, matching `chunked` exactly and case-insensitively. The only supported coding is `chunked`, and it must be the final coding. A value naming a coding Stallion does not implement (for example `gzip` or `x-chunked-fake`) is answered with `501 Not Implemented`. A value that cannot frame the message — empty, `chunked` listed more than once, or `chunked` applied before another coding — is answered with `400 Bad Request`. In both cases the connection is closed instead of hanging.

## Fix Connection: close handling

Stallion recognized a `Connection: close` (or `keep-alive`) directive only when it was the sole value on a single `Connection` header line. A `close` token alongside other options — `Connection: close, x-fake-option` or `Connection: keep-alive, close` — was ignored, as was a `close` sent on a second `Connection` line, so the connection stayed open instead of closing after the response. Browsers and proxies routinely send multi-token Connection values such as `keep-alive, Upgrade` or `close, TE`, so this affected ordinary traffic, not just unusual requests.

Stallion now reads `Connection` as the comma-separated list it is and honors a `close` token wherever it appears — anywhere in the list, in any case, and across repeated `Connection` header lines. A `close` token always closes the connection, taking precedence over `keep-alive`.

As part of this, `Headers.get` now combines repeated lines of a comma-separated list header — such as `Connection`, `Accept`, or `Cache-Control` — into one value, joined by commas in the order the lines appeared, matching how those fields are defined. Headers that are not comma-separated lists, such as `Set-Cookie`, are unaffected and still return their first value.

