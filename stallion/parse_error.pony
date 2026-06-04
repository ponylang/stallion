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

primitive MalformedHeaders
  """
  Header syntax is invalid: missing colon, an obs-fold continuation line, or
  whitespace between a field name and its colon (RFC 9112 §5.1).
  """
  fun string(): String iso^ => "MalformedHeaders".clone()

primitive InvalidContentLength
  """Content-Length is non-numeric, negative, or has conflicting values."""
  fun string(): String iso^ => "InvalidContentLength".clone()

primitive InvalidChunk
  """Chunked transfer encoding error: bad chunk size or missing CRLF."""
  fun string(): String iso^ => "InvalidChunk".clone()

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
  (TooLarge | UnknownMethod | InvalidURI | InvalidVersion | MalformedHeaders
  | InvalidContentLength | InvalidChunk | BodyTooLarge
  | InvalidTransferEncoding | UnsupportedTransferEncoding
  | ContentLengthWithTransferEncoding)
  """Parse error encountered during HTTP request parsing."""
