primitive ParseCookies
  """
  Parse cookies from HTTP request headers.

  Implements lenient parsing per RFC 6265 §5.4: splits on `;`, uses the
  first `=` as the name-value delimiter, trims whitespace, strips surrounding
  double quotes from values, and skips entries with empty names or missing `=`.

  This is a total function — it never errors. Malformed cookie strings produce
  an empty or partial `RequestCookies` collection rather than an error.

  Two entry points:

  * `from_headers()` — extracts and parses all `Cookie` headers from a
    `Headers val` collection. This is what `HTTPServer` uses internally.
  * `apply()` — parses a single `Cookie` header value string. Useful for
    testing or when you already have the raw header value.
  """

  fun from_headers(headers: Headers val): RequestCookies val =>
    """
    Parse all `Cookie` headers from the given header collection.

    Multiple `Cookie` headers are concatenated per RFC 6265 §5.4.
    """
    let cookies: Array[RequestCookie val] val = recover val
      let arr = Array[RequestCookie val]
      for hdr in headers.values() do
        if hdr.name == "cookie" then
          _parse_into(hdr.value, arr)
        end
      end
      arr
    end
    RequestCookies._create(cookies)

  fun apply(header_value: String val): RequestCookies val =>
    """Parse a single `Cookie` header value string."""
    let cookies: Array[RequestCookie val] val = recover val
      let arr = Array[RequestCookie val]
      _parse_into(header_value, arr)
      arr
    end
    RequestCookies._create(cookies)

  fun _parse_into(
    header_value: String val,
    cookies: Array[RequestCookie val] ref)
  =>
    """Parse cookie pairs from a header value and append to the array."""
    // Split on ";"
    var start: USize = 0
    let size = header_value.size()

    while start < size do
      // Find next ";"
      var semi: USize = start
      while (semi < size) and try header_value(semi)? != ';' else false end do
        semi = semi + 1
      end

      // Extract the segment and trim whitespace
      let segment = header_value.trim(start, semi)
      let trimmed = _trim_whitespace(segment)

      if trimmed.size() > 0 then
        // Find first "="
        var eq: USize = 0
        let tsize = trimmed.size()
        while (eq < tsize) and
          try trimmed(eq)? != '=' else false end
        do
          eq = eq + 1
        end

        if eq < tsize then
          let name = _trim_whitespace(trimmed.trim(0, eq))
          var value = _trim_whitespace(trimmed.trim(eq + 1))

          // Strip surrounding double quotes
          if (value.size() >= 2) and
            try (value(0)? == '"') and
              (value(value.size() - 1)? == '"')
            else false end
          then
            value = value.trim(1, value.size() - 1)
          end

          if name.size() > 0 then
            cookies.push(RequestCookie._create(name, value))
          end
        end
      end

      start = semi + 1
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
