primitive _ErrorResponse
  """
  Pre-built HTTP error response strings for parse errors.

  All responses are string literals — zero allocation at runtime.
  Each includes `Connection: close` and `Content-Length: 0` since the
  connection is always closed after a parse error.
  """

  fun for_error(err: ParseError): String val =>
    """Map a parse error to the appropriate HTTP error response."""
    match err
    | TooLarge =>
      "HTTP/1.1 431 Request Header Fields Too Large\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
    | BodyTooLarge =>
      "HTTP/1.1 413 Payload Too Large\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
    | InvalidVersion =>
      "HTTP/1.1 505 HTTP Version Not Supported\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
    else
      "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
    end

  fun no_response(): String val =>
    """
    Response sent when the pending request limit is exceeded.

    This is a server error (500) — the connection closes after sending.
    """
    "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
