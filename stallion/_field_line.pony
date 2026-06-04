class val _Field
  """
  A validated header or trailer field: a `1*tchar` name (lowercased) and a
  value free of CR, LF, and NUL.
  """
  let name: String val
  let value: String val

  new val create(name': String val, value': String val) =>
    name = name'
    value = value'

type _FieldResult is (_Field | InvalidFieldName | InvalidFieldValue | ObsFold)

primitive _FieldLine
  """
  RFC 9112 §5 field-line gate — the single place the field-line grammar is
  enforced, shared verbatim by header parsing and trailer parsing.

  The input is a `_ScannedLine` — a line already proven free of bare CR and LF
  by `_LineScan` (the type makes that a precondition the caller cannot skip), so
  this gate adds only the remaining rules: no obs-fold (a field-line beginning
  with SP/HTAB), a `1*tchar` name with no whitespace before the colon, and a
  value free of NUL. It does not re-scan for CR/LF — that rule lives in
  `_LineScan` alone. Because both the header state and the trailer state route
  through this one function, a tightening of the field-line grammar reaches both
  by construction; this is the structural fix for "the field-value fix never
  reached trailers".
  """
  fun parse(scanned: _ScannedLine): _FieldResult =>
    let line: String val = scanned.content
    if (line.size() > 0) and _OWS(try line(0)? else _Unreachable(); ' ' end) then
      return ObsFold
    end
    let colon = try line.find(":")?.usize() else return InvalidFieldName end
    let name = line.trim(0, colon)
    if not _Token.valid(name) then return InvalidFieldName end
    let value = _OWS.trim(line.trim(colon + 1))
    if not _FieldValue.valid(value) then return InvalidFieldValue end
    _Field(name.lower(), value)
