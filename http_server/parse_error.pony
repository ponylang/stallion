interface val _ParseError is Stringable

primitive TooLarge is _ParseError
  """Request line or headers exceed the configured size limit."""
  fun string(): String iso^ => "TooLarge".clone()

primitive UnknownMethod is _ParseError
  """HTTP method string not recognized."""
  fun string(): String iso^ => "UnknownMethod".clone()

primitive InvalidURI is _ParseError
  """Request URI is empty or contains spaces or control characters."""
  fun string(): String iso^ => "InvalidURI".clone()

primitive InvalidVersion is _ParseError
  """HTTP version is not HTTP/1.0 or HTTP/1.1."""
  fun string(): String iso^ => "InvalidVersion".clone()

primitive MalformedHeaders is _ParseError
  """Header syntax is invalid (missing colon, obs-fold continuation line)."""
  fun string(): String iso^ => "MalformedHeaders".clone()

primitive InvalidContentLength is _ParseError
  """Content-Length is non-numeric, negative, or has conflicting values."""
  fun string(): String iso^ => "InvalidContentLength".clone()

primitive InvalidChunk is _ParseError
  """Chunked transfer encoding error: bad chunk size or missing CRLF."""
  fun string(): String iso^ => "InvalidChunk".clone()

primitive BodyTooLarge is _ParseError
  """Request body exceeds the configured maximum body size."""
  fun string(): String iso^ => "BodyTooLarge".clone()

type ParseError is
  ((TooLarge | UnknownMethod | InvalidURI | InvalidVersion | MalformedHeaders
  | InvalidContentLength | InvalidChunk | BodyTooLarge) & _ParseError)
  """Parse error encountered during HTTP request parsing."""
