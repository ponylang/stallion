class val _ParserConfig
  """
  Configuration for HTTP request parser size limits.

  All limits are in bytes. Requests exceeding any limit produce a parse error.
  """
  let max_request_line_size: USize
  let max_header_size: USize
  let max_chunk_header_size: USize
  let max_body_size: USize

  new val create(
    max_request_line_size': USize = 8192,
    max_header_size': USize = 8192,
    max_chunk_header_size': USize = 128,
    max_body_size': USize = 1_048_576)
  =>
    max_request_line_size = max_request_line_size'
    max_header_size = max_header_size'
    max_chunk_header_size = max_chunk_header_size'
    max_body_size = max_body_size'
