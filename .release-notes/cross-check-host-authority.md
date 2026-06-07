## Reject requests with a contradictory Host or an incomplete CONNECT target

When a request-target carries its own authority — an absolute-form target like `GET http://example.com/`, or the authority-form target of a CONNECT request — Stallion previously accepted the request even when the `Host` header named a different host, and accepted a CONNECT target that omitted its port. Both are now rejected with `400 Bad Request`.

A `Host` that disagrees with the authority in the request-target gives a request two conflicting host identities. When Stallion sits behind or in front of another HTTP processor that picks the other identity, the two can be desynchronized — a request-routing and smuggling hazard. Stallion now requires the `Host` value and the request-target authority to name the same host. The comparison is case-insensitive and treats a missing port as the scheme's default, so `Host: example.com` still matches an `http://example.com:80/` target.

A CONNECT request-target must include the destination port, for example `CONNECT example.com:443`. A CONNECT target with no port, such as `CONNECT example.com` or `CONNECT example.com:`, is now rejected.

Stallion also rejects any request-target whose authority carries a userinfo component (anything before an `@`), such as `GET http://user@example.com/`. Userinfo is deprecated in `http`/`https` URLs and has no place in a CONNECT target; its presence obscures the real host and is a known way to disguise the authority, so the request is answered with `400 Bad Request`.
