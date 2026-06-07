primitive TooLarge
  """Request line or headers exceed the configured size limit."""
  fun string(): String iso^ => "TooLarge".clone()

primitive UnknownMethod
  """HTTP method string not recognized."""
  fun string(): String iso^ => "UnknownMethod".clone()

primitive InvalidURI
  """
  Request URI is invalid.

  Raised when the URI is empty, contains control characters, or fails
  RFC 3986 structural parsing in the connection layer (e.g., invalid
  authority in CONNECT targets).
  """
  fun string(): String iso^ => "InvalidURI".clone()

primitive InvalidVersion
  """HTTP version is not HTTP/1.0 or HTTP/1.1."""
  fun string(): String iso^ => "InvalidVersion".clone()

primitive BareCRLF
  """
  A bare CR or bare LF appears inside a protocol line.

  Only CRLF terminates a line. A lone CR (not immediately followed by LF) or a
  lone LF anywhere in the request line, a header or trailer field-line, or a
  chunk-size/extension line is rejected (RFC 9110 §5.5, RFC 9112 §2.2/§5).
  Treating a bare CR or LF as a line boundary is a request-smuggling vector: an
  intermediary that splits on it sees a message boundary where Stallion would
  not, desynchronizing the two.
  """
  fun string(): String iso^ => "BareCRLF".clone()

primitive InvalidFieldName
  """
  A header or trailer field name is not a valid token.

  The name must be `1*tchar` (RFC 9110 §5.6.2, RFC 9112 §5.1). Rejected: a
  non-token character, interior whitespace, whitespace between the name and the
  colon, an empty name, or a missing colon.
  """
  fun string(): String iso^ => "InvalidFieldName".clone()

primitive InvalidFieldValue
  """
  A header or trailer field value contains a forbidden byte.

  RFC 9110 §5.5 requires rejecting a field value containing NUL. (Bare CR and
  LF in a value are caught earlier by the line policy as `BareCRLF`; this error
  covers the remaining forbidden byte, NUL.)
  """
  fun string(): String iso^ => "InvalidFieldValue".clone()

primitive ObsFold
  """
  A header or trailer field uses obsolete line folding.

  An obs-fold continuation line (a field-line beginning with SP or HTAB) is
  rejected per RFC 9112 §5.2.
  """
  fun string(): String iso^ => "ObsFold".clone()

primitive InvalidRequestLine
  """
  The request line is not `method SP request-target SP HTTP-version CRLF`.

  Exactly one space separates each component (RFC 9112 §3). A different number
  of spaces — extra delimiters, or a space inside the request-target — is a
  framing violation and is rejected here.
  """
  fun string(): String iso^ => "InvalidRequestLine".clone()

primitive InvalidContentLength
  """Content-Length is non-numeric, negative, or has conflicting values."""
  fun string(): String iso^ => "InvalidContentLength".clone()

primitive InvalidChunk
  """
  A chunk-size line is malformed.

  The chunk-size must be `1*HEXDIG` (RFC 9112 §7.1). Rejected: a non-hex chunk
  size, garbage after the size, an empty size line, or a missing CRLF after the
  chunk data. (Forbidden bytes in a chunk extension are `InvalidChunkExtension`;
  a bare CR or LF in a chunk line is `BareCRLF`.)
  """
  fun string(): String iso^ => "InvalidChunk".clone()

primitive InvalidChunkExtension
  """
  A chunk extension contains forbidden or malformed bytes.

  A chunk-ext is `*( BWS ";" BWS chunk-ext-name [ BWS "=" BWS chunk-ext-val ] )`
  where names are tokens and values are token or quoted-string (RFC 9112 §7.1.1).
  Optional whitespace within the extension list is tolerated; whitespace between
  the chunk-size and the first `;` is rejected as `InvalidChunk` (RFC 9110 §5.6.3
  permits rejecting BWS). Unvalidated chunk-extension bytes are a smuggling
  surface, so they are parsed rather than skipped to CRLF.
  """
  fun string(): String iso^ => "InvalidChunkExtension".clone()

primitive BodyTooLarge
  """Request body exceeds the configured maximum body size."""
  fun string(): String iso^ => "BodyTooLarge".clone()

primitive InvalidTransferEncoding
  """
  Transfer-Encoding is syntactically valid but cannot frame the message.

  Raised when the field is empty, lists `chunked` more than once, or
  applies `chunked` before the final coding (RFC 9112 §6.1/§6.3). The
  message length is undeterminable, so the request is rejected.
  """
  fun string(): String iso^ => "InvalidTransferEncoding".clone()

primitive UnsupportedTransferEncoding
  """
  Transfer-Encoding names a transfer coding the server does not implement.

  Stallion only understands `chunked`. Any other coding (e.g. `gzip`),
  alone or alongside `chunked`, is rejected per RFC 9112 §6.3.
  """
  fun string(): String iso^ => "UnsupportedTransferEncoding".clone()

primitive ForbiddenTrailer
  """
  A trailer field carries a name that is not allowed in a trailer section.

  RFC 9110 §6.5.1 forbids trailer fields that affect message framing, routing,
  request modifiers, authentication, or payload processing — for example
  `Transfer-Encoding`, `Content-Length`, and `Host`. A recipient must reject or
  ignore such a trailer; Stallion rejects, because honoring a framing field that
  arrives *after* the body is a request-smuggling vector. The trailer field's
  syntax may be perfectly valid — the fault is the field's presence in a
  trailer.
  """
  fun string(): String iso^ => "ForbiddenTrailer".clone()

primitive BadHostHeader
  """
  A request's Host header field is missing (HTTP/1.1) or duplicated (any version).

  RFC 9110 §7.2 / RFC 9112 §3.2 require every HTTP/1.1 request to carry exactly
  one Host field; a server must answer 400 to one that lacks Host or has more
  than one. Stallion also rejects a duplicate Host on HTTP/1.0 — a second Host
  line is request-smuggling surface regardless of version. Enforced at the
  protocol layer (where the assembled headers are known), not the parser.
  """
  fun string(): String iso^ => "BadHostHeader".clone()

primitive InvalidHostValue
  """
  A request's Host header field value is not a well-formed host.

  RFC 9110 §7.2 / RFC 9112 §3.2 require the Host value to be a `uri-host
  [ ":" port ]` (uri-host per RFC 3986 §3.2.2: an IP-literal, IPv4address, or
  reg-name, plus an optional `*DIGIT` port). A value that violates that
  grammar — for example `a, b` (the space is not a reg-name character) or a port
  that is non-numeric or greater than 65535 — is a 400. Distinct from
  `BadHostHeader`, which covers a missing or duplicated Host field rather than a
  malformed value. Enforced at the protocol layer (where the headers are known).
  """
  fun string(): String iso^ => "InvalidHostValue".clone()

primitive MismatchedHost
  """
  A request's Host header field value disagrees with the request-target
  authority.

  When the request-target carries its own authority (absolute-form, or the
  authority-form used by CONNECT), RFC 9110 §7.2 requires the client to send a
  Host value identical to that authority (excluding userinfo). A request that
  presents two disagreeing host identities is a routing-confusion /
  request-smuggling vector ("Host of Troubles"): a front-end and an origin can
  route or authorize on different identities and be desynchronized. No
  conformant client sends a disagreeing pair, so Stallion answers 400 — a
  security-over-conformance choice, sibling to the duplicate-Host rule.
  Comparison is case-insensitive with default-port normalization (see
  `_HostAuthorityMatch`). Distinct from `BadHostHeader` (presence/uniqueness)
  and `InvalidHostValue` (value syntax): here the value is well-formed but
  contradicts the target. Enforced at the protocol layer (where the target and
  headers are both known).
  """
  fun string(): String iso^ => "MismatchedHost".clone()

primitive MissingConnectPort
  """
  A CONNECT request-target lacks the required port.

  RFC 9112 §3.2 defines `authority-form = uri-host ":" port`, and RFC 9110 §9.3.6
  requires a CONNECT request-target to carry the host *and* port of the tunnel
  destination. A target with no port — whether the colon is absent
  (`example.com`) or the port is empty (`example.com:`) — does not satisfy the
  grammar and is a 400. Distinct from `InvalidURI`, which covers RFC 3986
  *structural* parse failure: a portless authority parses fine under RFC 3986
  and fails only the HTTP authority-form requirement.
  """
  fun string(): String iso^ => "MissingConnectPort".clone()

primitive UserinfoInTarget
  """
  A request-target authority carries a userinfo subcomponent.

  RFC 9110 §4.2.4 deprecates userinfo in `http`/`https` URIs: a client MUST NOT
  send it, and a recipient should treat its presence as an error, since it
  obscures the true authority (a phishing aid) and lets parties that split the
  authority on a different `@` derive different hosts — a routing-confusion /
  request-smuggling surface. The CONNECT authority-form grammar (RFC 9112
  §3.2.3, `uri-host ":" port`) has no userinfo at all. Stallion rejects any
  userinfo in the request-target authority with 400, for every request-target
  form, independent of the Host header.
  """
  fun string(): String iso^ => "UserinfoInTarget".clone()

primitive ContentLengthWithTransferEncoding
  """
  A request carries both Content-Length and Transfer-Encoding header fields.

  RFC 9112 §6.3 forbids this combination ("A sender MUST NOT send a
  Content-Length header field in any message that contains a
  Transfer-Encoding header field") because it is a request-smuggling vector:
  an intermediary that honors one header while Stallion honors the other can
  be desynchronized, letting a smuggled request slip past. Rather than pick a
  framing, Stallion rejects the message — the presence of both headers is
  itself the fault, regardless of what either header's value resolves to.
  """
  fun string(): String iso^ => "ContentLengthWithTransferEncoding".clone()

type ParseError is
  (TooLarge | UnknownMethod | InvalidURI | InvalidVersion
  | BareCRLF | InvalidFieldName | InvalidFieldValue | ObsFold
  | InvalidRequestLine | InvalidContentLength | InvalidChunk
  | InvalidChunkExtension | BodyTooLarge | InvalidTransferEncoding
  | UnsupportedTransferEncoding | ContentLengthWithTransferEncoding
  | ForbiddenTrailer | BadHostHeader | InvalidHostValue
  | MismatchedHost | MissingConnectPort | UserinfoInTarget)
  """Parse error encountered during HTTP request parsing."""
