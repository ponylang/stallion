trait ref _RequestParserNotify
  """
  Callback interface for the HTTP request parser.
  """

  fun ref request_received(
    method: Method,
    uri: String val,
    version: Version,
    headers: Headers val)
  """
  Called when the request line and all headers have been parsed.

  For requests with a body (Content-Length or Transfer-Encoding: chunked),
  `body_chunk` calls follow. For requests without a body,
  `request_complete` is called immediately after.
  """

  fun ref body_chunk(data: Array[U8] val)
  """
  Called for each chunk of request body data as it becomes available.

  Body data is delivered incrementally — not accumulated. The total body
  size equals the Content-Length or the sum of chunked transfer chunks.
  """

  fun ref request_complete()
  """
  Called when the entire request (including any body) has been received.

  After this call, the parser is ready to parse the next request on the
  same connection (HTTP pipelining).
  """

  fun ref parse_error(err: ParseError)
  """
  Called when a parse error is encountered.

  After this call, the parser enters a terminal failed state and will not
  produce any further callbacks. The connection actor should send an
  appropriate error response (e.g., 400 Bad Request) and close.
  """
