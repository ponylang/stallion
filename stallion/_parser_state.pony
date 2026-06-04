primitive _ParseContinue
  """More data may be parseable in the current buffer."""

primitive _ParseNeedMore
  """Need more data from the network before parsing can continue."""

type _ParseResult is (_ParseContinue | _ParseNeedMore | ParseError)
  """Result of a single parse step."""

interface ref _ParserState
  """
  A state in the HTTP request parser state machine.

  Each state is a thin driver: it obtains protocol lines from `_LineScan` (the
  single CR/LF policy) and field-lines from `_FieldLine` (the single field-line
  gate), then transitions. No state interprets CR/LF or re-implements field-line
  grammar itself — that is what makes every grammar rule enforced in exactly one
  place. Per-state data (accumulators, counters) is owned by the state object and
  released automatically on transition.
  """
  fun ref parse(p: _RequestParser ref): _ParseResult

// ---------------------------------------------------------------------------
// Request line
// ---------------------------------------------------------------------------

class _ExpectRequestLine is _ParserState
  """Initial state: waiting for a complete request line."""
  fun ref parse(p: _RequestParser ref): _ParseResult =>
    match _LineScan.next(p.buf, p.pos, p.config.max_request_line_size)
    | let line: _Line =>
      match _RequestLine.parse(
        p.scanned_line(line))
      | (let m: Method, let target: String val, let v: Version) =>
        p.pos = line.next_pos()
        p.state = _ExpectHeaders(m, target, v, p.config)
        _ParseContinue
      | let e: ParseError => e
      end
    | BareCRLF => BareCRLF
    | _LineTooLong => TooLarge
    | _LineNeedMore => _ParseNeedMore
    end

// ---------------------------------------------------------------------------
// Headers
// ---------------------------------------------------------------------------

class _ExpectHeaders is _ParserState
  """
  Parsing header field-lines until the empty line ends the header section.

  Tracks Content-Length and Transfer-Encoding so the body framing can be
  resolved once, at the blank line, before the request is delivered.
  """
  let _method: Method
  let _target: String val
  let _version: Version
  let _config: _ParserConfig
  var _headers: Headers iso = recover iso Headers end
  var _content_length: (USize | None) = None
  var _has_transfer_encoding: Bool = false
  embed _te_codings: Array[String] = Array[String]
  var _te_well_formed: Bool = true
  var _header_bytes_used: USize = 0

  new create(
    method': Method,
    target': String val,
    version': Version,
    config: _ParserConfig)
  =>
    _method = method'
    _target = target'
    _version = version'
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    while true do
      match _LineScan.next(p.buf, p.pos, _config.max_header_size)
      | let line: _Line =>
        if line.is_blank() then
          p.pos = line.next_pos()
          return _finish(p)
        end

        let line_len = (line.content_end - line.content_start) + 2
        _header_bytes_used = _header_bytes_used + line_len
        if _header_bytes_used > _config.max_header_size then
          return TooLarge
        end

        match _FieldLine.parse(
          p.scanned_line(line))
        | let f: _Field =>
          match _track(f)
          | let e: ParseError => return e
          end
          // `_FieldLine` already lowercased the name; skip Headers' re-lower.
          _headers._add_lowered(f.name, f.value)
        | let e: ParseError => return e
        end

        p.pos = line.next_pos()
      | BareCRLF => return BareCRLF
      | _LineTooLong => return TooLarge
      | _LineNeedMore => return _ParseNeedMore
      end
    end
    _Unreachable()
    _ParseNeedMore

  fun ref _track(f: _Field): (None | ParseError) =>
    """Record Content-Length / Transfer-Encoding from a recognized field."""
    if f.name == "content-length" then
      match _parse_content_length(f.value)
      | let cl: USize =>
        match _content_length
        | let existing: USize =>
          if existing != cl then return InvalidContentLength end
        | None =>
          _content_length = cl
        end
      | InvalidContentLength => return InvalidContentLength
      end
    elseif f.name == "transfer-encoding" then
      _has_transfer_encoding = true
      _te_well_formed =
        _TransferEncoding.append_codings(f.value, _te_codings) and _te_well_formed
    end
    None

  fun ref _finish(p: _RequestParser ref): _ParseResult =>
    // RFC 9112 §6.3: Content-Length together with Transfer-Encoding is a
    // request-smuggling vector — reject rather than pick a framing (#114).
    if _has_transfer_encoding and (_content_length isnt None) then
      return ContentLengthWithTransferEncoding
    end

    // Body size limit (Content-Length) before delivery — the actor may respond
    // in on_request(), so a rejection must precede delivery.
    match _content_length
    | let cl: USize if cl > _config.max_body_size => return BodyTooLarge
    end

    // Resolve Transfer-Encoding framing (501/400 rejected before delivery).
    let use_chunked: Bool =
      if _has_transfer_encoding then
        match _TransferEncoding.evaluate(_te_codings, _te_well_formed)
        | _ChunkedFraming => true
        | let e: ParseError => return e
        end
      else
        false
      end

    let headers: Headers val = (_headers = recover iso Headers end)
    p.handler.request_received(_method, _target, _version, headers)

    // The protocol layer may reject the request inside request_received (a Host
    // or URI failure calls parse_error → stop()). If so, do not transition to a
    // body state or fire request_complete — the request was never delivered.
    if p.failed() then return _ParseContinue end

    if use_chunked then
      p.state = _ExpectChunkHeader(0, _config)
      return _ParseContinue
    end

    match _content_length
    | let cl: USize if cl > 0 =>
      p.state = _ExpectFixedBody(cl)
      _ParseContinue
    else
      p.handler.request_complete()
      p.state = _ExpectRequestLine
      _ParseContinue
    end

  fun _parse_content_length(value: String val)
    : (USize | InvalidContentLength)
  =>
    """Parse a Content-Length value as a non-negative `1*DIGIT` integer."""
    if value.size() == 0 then return InvalidContentLength end
    try
      var i: USize = 0
      while i < value.size() do
        let ch = value(i)?
        if (ch < '0') or (ch > '9') then return InvalidContentLength end
        i = i + 1
      end
      value.read_int[USize]()?._1
    else
      InvalidContentLength
    end

// ---------------------------------------------------------------------------
// Fixed-length body
// ---------------------------------------------------------------------------

class _ExpectFixedBody is _ParserState
  """Reading a fixed-length body (Content-Length), delivered incrementally."""
  var _remaining: USize

  new create(remaining: USize) =>
    _remaining = remaining

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    let available = (p.buf.size() - p.pos).min(_remaining)
    if available > 0 then
      p.handler.body_chunk(p.extract_bytes(p.pos, p.pos + available))
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

// ---------------------------------------------------------------------------
// Chunked transfer encoding
// ---------------------------------------------------------------------------

class _ExpectChunkHeader is _ParserState
  """Expecting a chunk-size line: `chunk-size [ chunk-ext ] CRLF`."""
  var _total_body_received: USize
  let _config: _ParserConfig

  new create(total_body_received: USize, config: _ParserConfig) =>
    _total_body_received = total_body_received
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    match _LineScan.next(p.buf, p.pos, _config.max_chunk_header_size)
    | let line: _Line =>
      if line.is_blank() then return InvalidChunk end
      match _ChunkHeader.parse(
        p.scanned_line(line))
      | let chunk_size: USize =>
        p.pos = line.next_pos()
        if chunk_size == 0 then
          p.state = _ExpectChunkTrailer(0, _config)
          _ParseContinue
        else
          // Checked addition: a chunk-size near USize.max (a 16-HEXDIG line,
          // which fits within max_chunk_header_size) would wrap the body-size
          // limit with plain `+`, silently defeating max_body_size. Fail closed
          // on overflow.
          (let total, let overflow) = _total_body_received.addc(chunk_size)
          if overflow or (total > _config.max_body_size) then
            return BodyTooLarge
          end
          p.state =
            _ExpectChunkData(chunk_size, _total_body_received, _config)
          _ParseContinue
        end
      | let e: ParseError => e
      end
    | BareCRLF => BareCRLF
    | _LineTooLong => InvalidChunk
    | _LineNeedMore => _ParseNeedMore
    end

class _ExpectChunkData is _ParserState
  """
  Reading chunk data, delivered incrementally, then the mandatory CRLF.

  The post-data terminator must be exactly CRLF (RFC 9112 §7.1) — it is not a
  general line, so it is checked directly rather than via `_LineScan`; any other
  bytes are `InvalidChunk`.
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
        p.handler.body_chunk(p.extract_bytes(p.pos, p.pos + available))
        p.pos = p.pos + available
        _remaining = _remaining - available
        _total_body_received = _total_body_received + available
      end
      if _remaining > 0 then
        return _ParseNeedMore
      end
    end

    if (p.buf.size() - p.pos) < 2 then
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
  Reading the optional trailer section after the last chunk.

  Trailer field-lines pass through the SAME `_FieldLine` gate as headers, plus
  the forbidden-trailer rule (RFC 9110 §6.5.1). Trailers are validated but not
  delivered (the callback contract has no trailer event). The request completes
  at the empty line.
  """
  var _trailer_bytes_used: USize
  let _config: _ParserConfig

  new create(trailer_bytes_used: USize, config: _ParserConfig) =>
    _trailer_bytes_used = trailer_bytes_used
    _config = config

  fun ref parse(p: _RequestParser ref): _ParseResult =>
    while true do
      match _LineScan.next(p.buf, p.pos, _config.max_header_size)
      | let line: _Line =>
        if line.is_blank() then
          p.pos = line.next_pos()
          p.handler.request_complete()
          p.state = _ExpectRequestLine
          return _ParseContinue
        end

        let line_len = (line.content_end - line.content_start) + 2
        _trailer_bytes_used = _trailer_bytes_used + line_len
        if _trailer_bytes_used > _config.max_header_size then
          return TooLarge
        end

        match _FieldLine.parse(
          p.scanned_line(line))
        | let f: _Field =>
          if _ForbiddenTrailers(f.name) then return ForbiddenTrailer end
        | let e: ParseError => return e
        end

        p.pos = line.next_pos()
      | BareCRLF => return BareCRLF
      | _LineTooLong => return TooLarge
      | _LineNeedMore => return _ParseNeedMore
      end
    end
    _Unreachable()
    _ParseNeedMore
