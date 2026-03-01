primitive _ParseContinue
  """More data may be parseable in the current buffer."""

primitive _ParseNeedMore
  """Need more data from the network before parsing can continue."""

type _ParseResult is (_ParseContinue | _ParseNeedMore | ParseError)
  """Result of a single parse step."""

interface ref _ParserState
  """
  A state in the HTTP request parser state machine.

  Each state is a class that owns its per-state data (buffers,
  accumulators). State transitions are explicit assignments to
  `p.state`. Per-state data is automatically cleaned up when
  the state transitions out.
  """
  fun ref parse(p: _RequestParser ref): _ParseResult

// ---------------------------------------------------------------------------
// Buffer scanning utilities
// ---------------------------------------------------------------------------

primitive _BufferScan
  """Byte-level scanning utilities for the parser buffer."""

  fun find_crlf(buf: Array[U8] box, from: USize = 0): (USize | None) =>
    """
    Find the position of \\r\\n in buf starting from `from`.
    Returns the index of \\r, or None if not found.
    """
    if buf.size() < (from + 2) then return None end
    var i = from
    let limit = buf.size() - 1
    try
      while i < limit do
        if (buf(i)? == '\r') and (buf(i + 1)? == '\n') then
          return i
        end
        i = i + 1
      end
    else
      _Unreachable()
    end
    None

  fun find_byte(
    buf: Array[U8] box,
    byte: U8,
    from: USize,
    to: USize = USize.max_value())
    : (USize | None)
  =>
    """Find the first occurrence of `byte` in buf[from, to)."""
    var i = from
    let limit = to.min(buf.size())
    try
      while i < limit do
        if buf(i)? == byte then return i end
        i = i + 1
      end
    else
      _Unreachable()
    end
    None

// ---------------------------------------------------------------------------
// Parser states
// ---------------------------------------------------------------------------

class _ExpectRequestLine is _ParserState
  """
  Initial state: waiting for a complete HTTP request line.

  Format: METHOD SP request-target SP HTTP-version CRLF
  """
  fun ref parse(p: _RequestParser ref): _ParseResult =>
    let available = p.buf.size() - p.pos

    // Check for CRLF marking end of request line
    match \exhaustive\ _BufferScan.find_crlf(p.buf, p.pos)
    | let crlf: USize =>
      let line_len = crlf - p.pos
      if line_len > p.config.max_request_line_size then
        return TooLarge
      end

      // Find first space: separates method from URI
      let method_end = match \exhaustive\ _BufferScan.find_byte(p.buf, ' ', p.pos, crlf)
        | let i: USize => i
        | None => return UnknownMethod
        end

      // Parse method
      let method_str: String val = p.extract_string(p.pos, method_end)
      let method = match \exhaustive\ Methods.parse(method_str)
        | let m: Method => m
        | None => return UnknownMethod
        end

      // Skip space(s) after method
      var uri_start = method_end + 1
      try
        while (uri_start < crlf) and (p.buf(uri_start)? == ' ') do
          uri_start = uri_start + 1
        end
      else
        _Unreachable()
      end

      // Find second space: separates URI from version
      let uri_end = match \exhaustive\ _BufferScan.find_byte(p.buf, ' ', uri_start, crlf)
        | let i: USize => i
        | None => return InvalidVersion
        end

      // Extract and validate URI
      if uri_end == uri_start then
        return InvalidURI
      end

      let uri: String val = p.extract_string(uri_start, uri_end)

      // Validate URI: no control characters (< 0x21 or > 0x7E)
      try
        var i: USize = 0
        while i < uri.size() do
          let ch = uri(i)?
          if (ch < 0x21) or (ch > 0x7E) then
            return InvalidURI
          end
          i = i + 1
        end
      else
        _Unreachable()
      end

      // Skip space(s) before version
      var ver_start = uri_end + 1
      try
        while (ver_start < crlf) and (p.buf(ver_start)? == ' ') do
          ver_start = ver_start + 1
        end
      else
        _Unreachable()
      end

      // Parse version: must be exactly "HTTP/1.0" or "HTTP/1.1"
      let ver_len = crlf - ver_start
      if ver_len != 8 then
        return InvalidVersion
      end

      let version = try
        if (p.buf(ver_start)? == 'H')
          and (p.buf(ver_start + 1)? == 'T')
          and (p.buf(ver_start + 2)? == 'T')
          and (p.buf(ver_start + 3)? == 'P')
          and (p.buf(ver_start + 4)? == '/')
          and (p.buf(ver_start + 5)? == '1')
          and (p.buf(ver_start + 6)? == '.')
        then
          let minor = p.buf(ver_start + 7)?
          if minor == '1' then
            HTTP11
          elseif minor == '0' then
            HTTP10
          else
            return InvalidVersion
          end
        else
          return InvalidVersion
        end
      else
        _Unreachable()
        return InvalidVersion
      end

      // Advance past the request line (including CRLF)
      p.pos = crlf + 2

      // Transition to header parsing
      p.state = _ExpectHeaders(method, uri, version, p.config)
      _ParseContinue

    | None =>
      // No complete line yet — check size limit
      if available > p.config.max_request_line_size then
        TooLarge
      else
        _ParseNeedMore
      end
    end

class _ExpectHeaders is _ParserState
  """
  Parsing HTTP headers after the request line.

  Loops through header lines until an empty line (CRLF) marks the end
  of headers. Tracks Content-Length and Transfer-Encoding for body handling.
  """
  let _method: Method
  let _uri: String val
  let _version: Version
  let _config: _ParserConfig
  var _headers: Headers iso = recover iso Headers end
  var _content_length: (USize | None) = None
  var _chunked: Bool = false
  var _total_header_bytes: USize = 0

  new create(
    method: Method,
    uri: String val,
    version: Version,
    config: _ParserConfig)
  =>
    _method = method
    _uri = uri
    _version = version
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    // Loop through header lines
    while true do
      match \exhaustive\ _BufferScan.find_crlf(p.buf, p.pos)
      | let crlf: USize =>
        if crlf == p.pos then
          // Empty line: end of headers
          p.pos = crlf + 2

          // Check body size limit before delivering the request. The actor
          // can now respond in on_request(), so rejections must precede delivery.
          match _content_length
          | let cl: USize if cl > _config.max_body_size =>
            return BodyTooLarge
          end

          // Destructive read: swap out headers as val, replace with empty
          let headers: Headers val =
            (_headers = recover iso Headers end)

          // Deliver the request metadata
          p.handler.request_received(_method, _uri, _version, headers)

          // Determine body handling: Transfer-Encoding takes precedence
          // over Content-Length per RFC 7230 §3.3.3
          if _chunked then
            p.state = _ExpectChunkHeader(0, _config)
            return _ParseContinue
          end

          match \exhaustive\ _content_length
          | let cl: USize if cl > 0 =>
            p.state = _ExpectFixedBody(cl)
            return _ParseContinue
          else
            // No body (no Content-Length, Content-Length: 0, or None)
            p.handler.request_complete()
            p.state = _ExpectRequestLine
            return _ParseContinue
          end
        end

        // Track header size
        let line_len = (crlf - p.pos) + 2
        _total_header_bytes = _total_header_bytes + line_len
        if _total_header_bytes > _config.max_header_size then
          return TooLarge
        end

        // Check for obs-fold (continuation line): reject per RFC 7230
        try
          let first_byte = p.buf(p.pos)?
          if (first_byte == ' ') or (first_byte == '\t') then
            return MalformedHeaders
          end
        else
          _Unreachable()
        end

        // Find colon separator
        let colon_pos = match \exhaustive\ _BufferScan.find_byte(p.buf, ':', p.pos, crlf)
          | let i: USize => i
          | None => return MalformedHeaders
          end

        // Header name must not be empty
        if colon_pos == p.pos then
          return MalformedHeaders
        end

        // Extract header name (lowercasing happens in Headers.add)
        let name: String val = p.extract_string(p.pos, colon_pos)

        // Extract header value, skipping optional whitespace (OWS)
        var val_start = colon_pos + 1
        try
          while val_start < crlf do
            let ch = p.buf(val_start)?
            if (ch != ' ') and (ch != '\t') then break end
            val_start = val_start + 1
          end
        else
          _Unreachable()
        end

        // Trim trailing OWS from value
        var val_end = crlf
        try
          while val_end > val_start do
            let ch = p.buf(val_end - 1)?
            if (ch != ' ') and (ch != '\t') then break end
            val_end = val_end - 1
          end
        else
          _Unreachable()
        end

        let value: String val = p.extract_string(val_start, val_end)

        // Detect special headers
        let lower_name: String val = name.lower()
        if lower_name == "content-length" then
          match \exhaustive\ _parse_content_length(value)
          | let cl: USize =>
            match \exhaustive\ _content_length
            | let existing: USize =>
              if existing != cl then
                return InvalidContentLength
              end
            | None =>
              _content_length = cl
            end
          | InvalidContentLength => return InvalidContentLength
          end
        elseif lower_name == "transfer-encoding" then
          if value.lower().contains("chunked") then
            _chunked = true
          end
        end

        _headers.add(name, value)

        // Advance past this header line
        p.pos = crlf + 2
      | None =>
        // No complete line yet — check size limit
        let pending = p.buf.size() - p.pos
        if (pending + _total_header_bytes) > _config.max_header_size then
          return TooLarge
        end
        return _ParseNeedMore
      end
    end
    _Unreachable()
    _ParseNeedMore

  fun _parse_content_length(value: String val)
    : (USize | InvalidContentLength)
  =>
    """Parse a Content-Length value as a non-negative integer."""
    if value.size() == 0 then
      return InvalidContentLength
    end
    try
      var i: USize = 0
      while i < value.size() do
        let ch = value(i)?
        if (ch < '0') or (ch > '9') then
          return InvalidContentLength
        end
        i = i + 1
      end
      value.read_int[USize]()?._1
    else
      InvalidContentLength
    end

class _ExpectFixedBody is _ParserState
  """
  Reading a fixed-length request body (Content-Length).

  Delivers body data incrementally as it becomes available in the buffer.
  """
  var _remaining: USize

  new create(remaining: USize) =>
    _remaining = remaining

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    let available = (p.buf.size() - p.pos).min(_remaining)
    if available > 0 then
      let chunk: Array[U8] val =
        p.extract_bytes(p.pos, p.pos + available)
      p.handler.body_chunk(chunk)
      p.pos = p.pos + available
      _remaining = _remaining - available
    end

    if _remaining == 0 then
      p.handler.request_complete()
      p.state = _ExpectRequestLine
      _ParseContinue
    else
      _ParseNeedMore
    end

class _ExpectChunkHeader is _ParserState
  """
  Expecting a chunk size line in chunked transfer encoding.

  Format: chunk-size [ chunk-ext ] CRLF
  """
  var _total_body_received: USize
  let _config: _ParserConfig

  new create(total_body_received: USize, config: _ParserConfig) =>
    _total_body_received = total_body_received
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    match \exhaustive\ _BufferScan.find_crlf(p.buf, p.pos)
    | let crlf: USize =>
      let line_len = crlf - p.pos
      if line_len > _config.max_chunk_header_size then
        return InvalidChunk
      end
      if line_len == 0 then
        return InvalidChunk
      end

      // Find optional chunk extension (semicolon)
      let size_end = match \exhaustive\ _BufferScan.find_byte(p.buf, ';', p.pos, crlf)
        | let i: USize => i
        | None => crlf
        end

      // Parse hex chunk size — must consume entire string
      let size_str: String val = p.extract_string(p.pos, size_end)
      let chunk_size = try
        (let cs, let consumed) = size_str.read_int[USize](0, 16)?
        if consumed.usize() != size_str.size() then
          return InvalidChunk
        end
        cs
      else
        return InvalidChunk
      end

      p.pos = crlf + 2

      if chunk_size == 0 then
        // Last chunk — expect trailers or final CRLF
        p.state = _ExpectChunkTrailer(0, _config)
        _ParseContinue
      else
        // Check body size limit
        if (_total_body_received + chunk_size) > _config.max_body_size then
          return BodyTooLarge
        end
        p.state = _ExpectChunkData(
          chunk_size, _total_body_received, _config)
        _ParseContinue
      end
    | None =>
      // No complete line — check size limit
      let pending = p.buf.size() - p.pos
      if pending > _config.max_chunk_header_size then
        InvalidChunk
      else
        _ParseNeedMore
      end
    end

class _ExpectChunkData is _ParserState
  """
  Reading chunk data in chunked transfer encoding.

  Delivers data incrementally, then expects CRLF after the chunk data.
  """
  var _remaining: USize
  var _total_body_received: USize
  let _config: _ParserConfig

  new create(
    remaining: USize,
    total_body_received: USize,
    config: _ParserConfig)
  =>
    _remaining = remaining
    _total_body_received = total_body_received
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    if _remaining > 0 then
      let available = (p.buf.size() - p.pos).min(_remaining)
      if available > 0 then
        let chunk: Array[U8] val =
          p.extract_bytes(p.pos, p.pos + available)
        p.handler.body_chunk(chunk)
        p.pos = p.pos + available
        _remaining = _remaining - available
        _total_body_received = _total_body_received + available
      end
      if _remaining > 0 then
        return _ParseNeedMore
      end
    end

    // Chunk data consumed — expect CRLF
    let bytes_available = p.buf.size() - p.pos
    if bytes_available < 2 then
      return _ParseNeedMore
    end

    try
      if (p.buf(p.pos)? == '\r') and (p.buf(p.pos + 1)? == '\n') then
        p.pos = p.pos + 2
        p.state = _ExpectChunkHeader(_total_body_received, _config)
        _ParseContinue
      else
        InvalidChunk
      end
    else
      _Unreachable()
      InvalidChunk
    end

class _ExpectChunkTrailer is _ParserState
  """
  Reading optional trailer headers after the last (zero-size) chunk.

  Trailers are skipped (not delivered to the receiver). The request is
  complete when an empty line is found.
  """
  var _total_trailer_bytes: USize
  let _config: _ParserConfig

  new create(total_trailer_bytes: USize, config: _ParserConfig) =>
    _total_trailer_bytes = total_trailer_bytes
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    while true do
      match \exhaustive\ _BufferScan.find_crlf(p.buf, p.pos)
      | let crlf: USize =>
        if crlf == p.pos then
          // Empty line: end of chunked message
          p.pos = crlf + 2
          p.handler.request_complete()
          p.state = _ExpectRequestLine
          return _ParseContinue
        end

        // Skip this trailer header line
        let line_len = (crlf - p.pos) + 2
        _total_trailer_bytes = _total_trailer_bytes + line_len
        if _total_trailer_bytes > _config.max_header_size then
          return TooLarge
        end

        p.pos = crlf + 2
      | None =>
        let pending = p.buf.size() - p.pos
        if (pending + _total_trailer_bytes) > _config.max_header_size then
          return TooLarge
        end
        return _ParseNeedMore
      end
    end
    _Unreachable()
    _ParseNeedMore

