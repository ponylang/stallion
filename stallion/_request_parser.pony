class _RequestParser
  """
  HTTP/1.1 request parser.

  Data is fed in as chunks via `parse()` (matching lori's delivery model).
  Parsed requests are delivered via the `_RequestParserNotify` callback
  interface. The parser handles arbitrary chunk boundaries, pipelining
  (multiple requests in one buffer), and both fixed-length and chunked
  transfer encoding.

  Fields are public so that state classes (in the same package)
  can access them for buffer reading, position tracking, state transitions,
  and handler callbacks.
  """
  var state: _ParserState = _ExpectRequestLine
  let handler: _RequestParserNotify ref
  let config: _ParserConfig
  var buf: Array[U8] ref = Array[U8]
  var pos: USize = 0
  var _failed: Bool = false

  new create(
    handler': _RequestParserNotify ref,
    config': _ParserConfig = _ParserConfig)
  =>
    handler = handler'
    config = config'

  fun ref parse(data: Array[U8] iso) =>
    """
    Feed data to the parser.

    The parser processes as much data as possible in a single call,
    delivering callbacks for each complete request (or request component)
    found. Remaining partial data is buffered for the next call.
    """
    // Short-circuit if parser has already failed (terminal state)
    if _failed then return end

    buf.append(consume data)

    // Parse loop: process data until we need more or hit an error
    var continue_parsing = true
    while continue_parsing do
      match \exhaustive\ state.parse(this)
      | _ParseContinue =>
        // A handler callback (triggered by state.parse) may have called
        // stop() — check before continuing to the next state transition.
        if _failed then break end
      | _ParseNeedMore => continue_parsing = false
      | let err: ParseError =>
        handler.parse_error(err)
        _failed = true
        continue_parsing = false
      end
    end

    // Compact consumed data
    if pos > 0 then
      buf.trim_in_place(pos)
      pos = 0
    end

  fun ref stop() =>
    """
    Stop the parser. All subsequent `parse()` calls become no-ops.

    Safe to call from within a handler callback during parsing — the parse
    loop checks the failed flag after each state transition.
    """
    _failed = true

  fun ref extract_bytes(from: USize, to: USize): Array[U8] iso^ =>
    """Copy bytes from buf[from..to) into a new iso array."""
    let len = to - from
    let out = recover Array[U8].create(len) end
    var i = from
    while i < to do
      try out.push(buf(i)?) else _Unreachable() end
      i = i + 1
    end
    out

  fun ref extract_string(from: USize, to: USize): String iso^ =>
    """Copy bytes from buf[from..to) into a new iso String."""
    let len = to - from
    let out = recover String.create(len) end
    var i = from
    while i < to do
      try out.push(buf(i)?) else _Unreachable() end
      i = i + 1
    end
    out
