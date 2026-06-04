type _ChunkHeaderResult is (USize | InvalidChunk | InvalidChunkExtension)

primitive _ChunkHeader
  """
  RFC 9112 §7.1 chunk header — `chunk-size [ chunk-ext ]`.

  The chunk-size is a strict `1*HEXDIG`: no `0x`/sign prefix, no trailing junk.
  The chunk-ext, if present, is validated against
  `*( ";" BWS chunk-ext-name [ BWS "=" BWS chunk-ext-val ] )` with token
  ext-names and token-or-quoted-string ext-vals — closing the chunk position
  that was previously skipped to CRLF unvalidated. The input is a `_ScannedLine`
  (produced by `_LineScan`), so a bad chunk line's bare CR/LF is already
  `BareCRLF` before this runs.
  """
  fun parse(scanned: _ScannedLine): _ChunkHeaderResult =>
    let line: String val = scanned.content
    let semi = try line.find(";")?.usize() else line.size() end
    let size_str = line.trim(0, semi)
    if size_str.size() == 0 then return InvalidChunk end
    // chunk-size is strictly `1*HEXDIG`. `read_int` alone is not enough: it
    // accepts `_` as a digit-group separator, so `5_0` would parse as 0x50 —
    // a smuggling vector (a strict intermediary chokes on `_` where Stallion
    // reads a length). Reject any non-HEXDIG byte first.
    for b in size_str.values() do
      if not _is_hexdig(b) then return InvalidChunk end
    end
    let chunk_size =
      try
        (let cs, let consumed) = size_str.read_int[USize](0, 16)?
        if consumed.usize() != size_str.size() then return InvalidChunk end
        cs
      else
        return InvalidChunk
      end
    if semi < line.size() then
      match _validate_ext(line.trim(semi))
      | let e: InvalidChunkExtension => return e
      end
    end
    chunk_size

  fun _validate_ext(ext: String val): (None | InvalidChunkExtension) =>
    """
    `ext` begins with the first `;`. Split on `;` (quoted-string aware, so a
    `;` inside an ext-val quoted-string does not split an extension), then
    validate each `BWS ext-name [ BWS "=" BWS ext-val ]` element.
    """
    (let segs, let unterminated) = _QuotedSplit(ext, ';')
    if unterminated then return InvalidChunkExtension end
    var first = true
    for seg in segs.values() do
      if first then
        // Text before the first `;` (there is none — `ext` starts with `;`).
        first = false
        if seg.size() != 0 then return InvalidChunkExtension end
      else
        if not _valid_ext_elem(seg) then return InvalidChunkExtension end
      end
    end
    None

  fun _valid_ext_elem(seg: String val): Bool =>
    let s = _OWS.trim(seg)
    if s.size() == 0 then return false end
    match try s.find("=")?.usize() else None end
    | let eq: USize =>
      _Token.valid(_OWS.trim(s.trim(0, eq)))
        and _valid_ext_val(_OWS.trim(s.trim(eq + 1)))
    | None =>
      _Token.valid(s)
    end

  fun _valid_ext_val(v: String val): Bool =>
    if (v.size() >= 2) and (try v(0)? == '"' else false end) then
      _valid_quoted_string(v)
    else
      _Token.valid(v)
    end

  fun _valid_quoted_string(v: String val): Bool =>
    """RFC 9110 §5.6.4 quoted-string: `DQUOTE *( qdtext / quoted-pair ) DQUOTE`."""
    let n = v.size()
    var i: USize = 1
    try
      while i < n do
        let c = v(i)?
        if c == '\\' then
          if (i + 1) >= n then return false end
          if not _quoted_pair_octet(v(i + 1)?) then return false end
          i = i + 2
        elseif c == '"' then
          return i == (n - 1)
        elseif not _qdtext(c) then
          return false
        else
          i = i + 1
        end
      end
    else
      return false
    end
    false

  fun _is_hexdig(b: U8): Bool =>
    ((b >= '0') and (b <= '9'))
      or ((b >= 'a') and (b <= 'f'))
      or ((b >= 'A') and (b <= 'F'))

  fun _qdtext(c: U8): Bool =>
    """HTAB / SP / %x21 / %x23-5B / %x5D-7E / obs-text."""
    (c == 0x09) or (c == 0x20) or (c == 0x21)
      or ((c >= 0x23) and (c <= 0x5B))
      or ((c >= 0x5D) and (c <= 0x7E))
      or (c >= 0x80)

  fun _quoted_pair_octet(c: U8): Bool =>
    """HTAB / SP / VCHAR / obs-text."""
    (c == 0x09) or (c == 0x20) or ((c >= 0x21) and (c <= 0x7E)) or (c >= 0x80)
