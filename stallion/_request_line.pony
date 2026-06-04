type _RequestLineResult is
  ( (Method, String val, Version)
  | UnknownMethod | InvalidRequestLine | InvalidURI | InvalidVersion )

primitive _RequestLine
  """
  RFC 9112 §3 request line — `method SP request-target SP HTTP-version`, with
  EXACTLY one SP between the three components. Any other SP count (a missing
  delimiter, an extra delimiter, or a space inside the request-target) is a
  framing violation (`InvalidRequestLine`).

  The request-target is validated only at the byte/framing level here: it must
  be a non-empty run of VCHARs (no controls, NUL, or non-ASCII; SP is already
  excluded by the split). That is the smuggling-relevant check, enforced where
  the bytes are. The target is delivered RAW; parsing it into a URI structure
  (origin/absolute/authority form) is the protocol layer's job.

  The input is a `_ScannedLine` (produced by `_LineScan`), so the request line
  is already free of bare CR/LF before this runs.
  """
  fun parse(scanned: _ScannedLine): _RequestLineResult =>
    let line: String val = scanned.content
    let sp1 = try line.find(" ")?.usize() else return InvalidRequestLine end
    let sp2 =
      try line.find(" ", (sp1 + 1).isize())?.usize()
      else return InvalidRequestLine
      end
    // A third SP means more than two delimiters — malformed framing.
    if (try line.find(" ", (sp2 + 1).isize())?; true else false end) then
      return InvalidRequestLine
    end

    let method_str = line.trim(0, sp1)
    let method' =
      match Methods.parse(method_str)
      | let m: Method => m
      | None =>
        // Not a method we implement. A valid token is an unimplemented method
        // (`UnknownMethod` → 501); a non-token is a malformed request line
        // (`InvalidRequestLine` → 400).
        if _Token.valid(method_str) then
          return UnknownMethod
        else
          return InvalidRequestLine
        end
      end

    let target = line.trim(sp1 + 1, sp2)
    match _valid_target(target)
    | let e: InvalidURI => return e
    end

    let version' =
      match _parse_version(line.trim(sp2 + 1))
      | let v: Version => v
      | None => return InvalidVersion
      end

    (method', target, version')

  fun _valid_target(target: String val): (None | InvalidURI) =>
    """
    Framing-level byte check: the request-target must be a non-empty run of
    VCHARs (0x21–0x7E). Controls (incl. NUL), DEL, and raw non-ASCII are
    rejected; conformant targets percent-encode them. Structural URI validity
    is left to the protocol layer.
    """
    if target.size() == 0 then return InvalidURI end
    for b in target.values() do
      if (b < 0x21) or (b > 0x7E) then return InvalidURI end
    end
    None

  fun _parse_version(s: String val): (Version | None) =>
    """Exactly `HTTP/1.0` or `HTTP/1.1`."""
    if s.size() != 8 then return None end
    try
      if (s(0)? == 'H') and (s(1)? == 'T') and (s(2)? == 'T')
        and (s(3)? == 'P') and (s(4)? == '/') and (s(5)? == '1')
        and (s(6)? == '.')
      then
        match s(7)?
        | '1' => HTTP11
        | '0' => HTTP10
        else None
        end
      else
        None
      end
    else
      None
    end
