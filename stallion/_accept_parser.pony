use "constrained_types"

primitive _AcceptParser
  """
  Parse an HTTP Accept header value into an array of `_AcceptRange` values.

  Implements lenient parsing: malformed entries are silently skipped rather
  than producing an error. Comma splitting is quoted-string-aware so that
  commas inside quoted parameter values don't split entries.
  """

  fun apply(header_value: String val): Array[_AcceptRange val] val =>
    """Parse a single Accept header value string."""
    let ranges = recover iso Array[_AcceptRange val] end
    let segments = _split_on_comma(header_value)
    for segment in segments.values() do
      let trimmed = _trim_whitespace(segment)
      if trimmed.size() > 0 then
        match _parse_range(trimmed)
        | let r: _AcceptRange val => ranges.push(r)
        end
      end
    end
    consume ranges

  fun _split_on_comma(s: String val): Array[String val] val =>
    """
    Split on commas, respecting quoted strings.

    Commas inside double-quoted parameter values are not treated as
    separators.
    """
    let result = recover iso Array[String val] end
    var start: USize = 0
    var i: USize = 0
    var in_quotes: Bool = false
    let size = s.size()

    while i < size do
      try
        let b = s(i)?
        if b == '"' then
          in_quotes = not in_quotes
        elseif (b == ',') and (not in_quotes) then
          result.push(s.trim(start, i))
          start = i + 1
        end
      end
      i = i + 1
    end
    result.push(s.trim(start, size))
    consume result

  fun _parse_range(segment: String val): (_AcceptRange val | None) =>
    """
    Parse a single media range segment like `text/html;level=1;q=0.9;ext=1`.

    Returns `None` if the segment is malformed (no slash, etc.).

    Per RFC 7231 §5.3.2, parameters before `q` are media type parameters
    (they affect matching), while parameters after `q` are accept extensions
    (they are ignored for matching purposes).
    """
    // Split off parameters at first semicolon
    var semi: USize = 0
    let size = segment.size()
    while (semi < size) and
      try segment(semi)? != ';' else false end
    do
      semi = semi + 1
    end

    let media_part = _trim_whitespace(segment.trim(0, semi))

    // Find the slash in type/subtype
    var slash: USize = 0
    let msize = media_part.size()
    while (slash < msize) and
      try media_part(slash)? != '/' else false end
    do
      slash = slash + 1
    end

    // Must have a slash and non-empty type and subtype
    if (slash == 0) or (slash >= (msize - 1)) then
      return None
    end

    let type_name: String val =
      _trim_whitespace(media_part.trim(0, slash)).lower()
    let subtype: String val =
      _trim_whitespace(media_part.trim(slash + 1)).lower()

    if (type_name.size() == 0) or (subtype.size() == 0) then
      return None
    end

    // */subtype is not valid per RFC 7231 — only */* is allowed
    if (type_name == "*") and (subtype != "*") then
      return None
    end

    // Parse parameters
    var quality: U16 = 1000  // default q=1.0
    var params = recover iso Array[(String val, String val)] end
    var found_q: Bool = false

    if semi < size then
      let param_str = segment.trim(semi + 1)
      let param_parts = _split_params(param_str)
      for part in param_parts.values() do
        let trimmed = _trim_whitespace(part)
        if trimmed.size() == 0 then continue end

        // Find the = in param
        var eq: USize = 0
        let psize = trimmed.size()
        while (eq < psize) and
          try trimmed(eq)? != '=' else false end
        do
          eq = eq + 1
        end

        if eq < psize then
          let pname: String val =
            _trim_whitespace(trimmed.trim(0, eq)).lower()
          let pval = _trim_whitespace(trimmed.trim(eq + 1))

          if (pname == "q") and (not found_q) then
            found_q = true
            quality = _parse_quality(pval)
          elseif not found_q then
            // Parameters before q are media type parameters
            params.push((pname, pval))
          end
          // Parameters after q are accept extensions — ignored
        end
      end
    end

    let params_val: Array[(String val, String val)] val = consume params

    match _MakeQuality(quality)
    | let q: _Quality =>
      _AcceptRange(type_name, subtype, params_val, q)
    else
      // Quality out of range — skip this entry
      None
    end

  fun _split_params(s: String val): Array[String val] val =>
    """Split parameter string on semicolons, respecting quoted strings."""
    let result = recover iso Array[String val] end
    var start: USize = 0
    var i: USize = 0
    var in_quotes: Bool = false
    let size = s.size()

    while i < size do
      try
        let b = s(i)?
        if b == '"' then
          in_quotes = not in_quotes
        elseif (b == ';') and (not in_quotes) then
          result.push(s.trim(start, i))
          start = i + 1
        end
      end
      i = i + 1
    end
    result.push(s.trim(start, size))
    consume result

  fun _parse_quality(s: String val): U16 =>
    """
    Parse a quality value string into a 0–1000 integer.

    Accepts formats like "1", "0.5", "0.99", "0.123". Values outside
    0.000–1.000 are clamped. Malformed values return 1000 (default).
    """
    let stripped = _strip_quotes(s)
    let qsize = stripped.size()
    if qsize == 0 then return 1000 end

    // Find the decimal point
    var dot: USize = qsize
    var i: USize = 0
    while i < qsize do
      try
        if stripped(i)? == '.' then
          dot = i
          break
        end
      end
      i = i + 1
    end

    // Parse integer part
    let int_part = stripped.trim(0, dot)
    var int_val: U16 = 0
    if int_part.size() > 0 then
      try
        let parsed = int_part.u16()?
        if parsed > 1 then return 1000 end
        int_val = parsed * 1000
      else
        return 1000
      end
    end

    if dot >= qsize then
      // No decimal part
      return int_val.min(1000)
    end

    // Parse fractional part — up to 3 digits
    let frac_part = stripped.trim(dot + 1)
    let fsize = frac_part.size()
    var frac_val: U16 = 0
    var digits: USize = 0
    var j: USize = 0
    while (j < fsize) and (digits < 3) do
      try
        let b = frac_part(j)?
        if (b >= '0') and (b <= '9') then
          frac_val = (frac_val * 10) + (b - '0').u16()
          digits = digits + 1
        else
          break
        end
      end
      j = j + 1
    end

    // No digits on either side of the dot — malformed
    if (int_part.size() == 0) and (digits == 0) then
      return 1000
    end

    // Scale to 3 decimal places
    while digits < 3 do
      frac_val = frac_val * 10
      digits = digits + 1
    end

    (int_val + frac_val).min(1000)

  fun _strip_quotes(s: String val): String val =>
    """Strip surrounding double quotes if present."""
    if (s.size() >= 2) and
      try (s(0)? == '"') and (s(s.size() - 1)? == '"') else false end
    then
      s.trim(1, s.size() - 1)
    else
      s
    end

  fun _trim_whitespace(s: String val): String val =>
    """Trim leading and trailing spaces and tabs."""
    var first: USize = 0
    var last: USize = s.size()
    while (first < last) and
      try
        let b = s(first)?
        (b == ' ') or (b == '\t')
      else false end
    do
      first = first + 1
    end
    while (last > first) and
      try
        let b = s(last - 1)?
        (b == ' ') or (b == '\t')
      else false end
    do
      last = last - 1
    end
    s.trim(first, last)
