primitive _HostValue
  """
  RFC 9110 §7.2 / RFC 9112 §3.2 Host field value validity.

  A `Host` field value is `uri-host [ ":" port ]`, where `uri-host` is
  `IP-literal / IPv4address / reg-name` (RFC 3986 §3.2.2):

  ```
  reg-name    = *( unreserved / pct-encoded / sub-delims )
  unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
  sub-delims  = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
  pct-encoded = "%" HEXDIG HEXDIG
  IP-literal  = "[" ( IPv6address / IPvFuture ) "]"
  port        = *DIGIT
  ```

  This is a purely syntactic gate, the single source for "what is a valid Host
  value". The protocol layer (`HTTPServer.request_received`) calls it after the
  Host presence/uniqueness check and rejects a malformed value with 400. It does
  NOT cross-check the value against an absolute-form or CONNECT authority in the
  request-target; that is a separate concern, handled by `_HostAuthorityMatch`.

  `IPv4address` is a character-subset of `reg-name` (DIGIT and `.`, both
  unreserved), so a syntactically valid IPv4 passes the reg-name check and needs
  no separate branch. A consequence: a malformed-looking dotted value such as
  `999.999.999.999` is accepted, because it is a valid `reg-name` — this gate
  validates host *syntax*, not IPv4 *semantics*. Only the bracketed IP-literal
  needs special handling.

  The empty value is valid (an empty `reg-name`); so is an empty host followed
  by an explicit port (`:80`), since the host component may be an empty
  reg-name. The port is validated to be
  all-DIGIT and `<= 65535`: this gate is the only place stallion ever validates
  the Host header's port (the range check in `uri`'s `ParseURIAuthority` runs on
  the request-*target* authority, never on the Host header), so the bound is
  enforced here to match the CONNECT path. An empty port (`host:`) is allowed.

  The IP-literal predicates mirror `ParseURIAuthority`'s exactly so the two
  host-validation paths behave identically.

  Validation is syntactic and ASCII-only. Percent-encoded octets are checked for
  the `"%" HEXDIG HEXDIG` shape but never decoded — a downstream that decodes
  and re-splits the result is the downstream's bug, not ours (the same stance
  the AGENTS.md conformance doctrine takes on an upstream that rewrites `_` to
  `-`).
  Non-ASCII obs-text (0x80–0xFF) is rejected because it is not an unreserved,
  sub-delim, or pct-encoded byte.
  """

  fun valid(s: String box): Bool =>
    """Whether `s` is a valid Host field value (`uri-host [ ":" port ]`)."""
    if s.size() == 0 then return true end // empty reg-name
    try
      if s(0)? == '[' then
        _ip_literal_host(s)
      else
        _reg_name_and_port(s)
      end
    else
      _Unreachable()
      false
    end

  fun _reg_name_and_port(s: String box): Bool =>
    // The first ":" (if any) delimits host from port. ":" is not a reg-name
    // character, so this is unambiguous; a second colon lands in the port part
    // and fails the DIGIT check.
    try
      var i: USize = 0
      var colon: USize = s.size() // sentinel: no port
      while i < s.size() do
        if s(i)? == ':' then
          colon = i
          break
        end
        i = i + 1
      end
      if colon == s.size() then
        _reg_name(s, 0, s.size())
      else
        _reg_name(s, 0, colon) and _port(s, colon + 1, s.size())
      end
    else
      _Unreachable()
      false
    end

  fun _ip_literal_host(s: String box): Bool =>
    // s(0) == '[' (guaranteed by the caller). Find the closing ']', validate
    // the bracket content as IPv6/IPvFuture, then accept end-of-string or
    // ":" port.
    try
      var rb: USize = 1
      var found = false
      while rb < s.size() do
        if s(rb)? == ']' then
          found = true
          break
        end
        rb = rb + 1
      end
      if not found then return false end

      let content: String val = s.substring(1, rb.isize())
      if not _valid_ip_literal(content) then return false end

      let after = rb + 1
      if after == s.size() then return true end
      if s(after)? != ':' then return false end
      _port(s, after + 1, s.size())
    else
      _Unreachable()
      false
    end

  fun _reg_name(s: String box, start: USize, stop: USize): Bool =>
    // *( unreserved / pct-encoded / sub-delims ) over [start, stop).
    try
      var i = start
      while i < stop do
        let c = s(i)?
        if c == '%' then
          // pct-encoded = "%" HEXDIG HEXDIG — both digits must be in range.
          if (i + 2) >= stop then return false end
          if not (_is_hexdig(s(i + 1)?) and _is_hexdig(s(i + 2)?)) then
            return false
          end
          i = i + 3
        elseif _is_unreserved(c) or _is_sub_delim(c) then
          i = i + 1
        else
          return false
        end
      end
      true
    else
      _Unreachable()
      false
    end

  fun _port(s: String box, start: USize, stop: USize): Bool =>
    // port = *DIGIT, additionally bounded to <= 65535. Empty port is valid.
    if start == stop then return true end

    // All characters must be DIGIT *before* parsing: `String.read_int` silently
    // ignores underscores, so without this guard "6_5" would parse as 65.
    try
      var i = start
      while i < stop do
        let c = s(i)?
        if (c < '0') or (c > '9') then return false end
        i = i + 1
      end
    else
      _Unreachable()
      return false
    end

    // read_int uses partial arithmetic, so an overflowing port errors
    // (rejected) rather than wrapping below the bound.
    let port_str: String val = s.substring(start.isize(), stop.isize())
    try
      port_str.u64()? <= 65535
    else
      false
    end

  fun _valid_ip_literal(content: String box): Bool =>
    if content.size() == 0 then
      return false
    end

    // IPvFuture starts with 'v' (case-insensitive); otherwise IPv6.
    try
      let first = content(0)?
      if (first == 'v') or (first == 'V') then
        return _valid_ipvfuture(content)
      end
    else
      _Unreachable() // content.size() > 0 guaranteed above
    end

    _valid_ipv6(content)

  fun _valid_ipv6(content: String box): Bool =>
    // Lenient: only HEXDIG, ':', and '.' (for IPv4-mapped forms).
    for c in content.values() do
      if not (
        ((c >= '0') and (c <= '9'))
          or ((c >= 'A') and (c <= 'F'))
          or ((c >= 'a') and (c <= 'f'))
          or (c == ':') or (c == '.'))
      then
        return false
      end
    end
    true

  fun _valid_ipvfuture(content: String box): Bool =>
    // IPvFuture = "v" 1*HEXDIG "." 1*( unreserved / sub-delims / ":" )
    // Minimum: "v" + HEXDIG + "." + one char = 4 chars.
    if content.size() < 4 then
      return false
    end

    var dot_pos: USize = 0
    var found_dot = false
    try
      var i: USize = 1 // skip 'v'
      while i < content.size() do
        if content(i)? == '.' then
          dot_pos = i
          found_dot = true
          break
        end
        i = i + 1
      end
    else
      _Unreachable()
    end

    if not found_dot then
      return false
    end

    // At least one HEXDIG between 'v' and '.'.
    if dot_pos < 2 then
      return false
    end

    try
      var i: USize = 1
      while i < dot_pos do
        if not _is_hexdig(content(i)?) then
          return false
        end
        i = i + 1
      end
    else
      _Unreachable()
    end

    // At least one char after '.'.
    if (dot_pos + 1) >= content.size() then
      return false
    end

    try
      var i: USize = dot_pos + 1
      while i < content.size() do
        let c = content(i)?
        if not (_is_unreserved(c) or _is_sub_delim(c) or (c == ':')) then
          return false
        end
        i = i + 1
      end
    else
      _Unreachable()
    end

    true

  fun _is_hexdig(c: U8): Bool =>
    ((c >= '0') and (c <= '9'))
      or ((c >= 'A') and (c <= 'F'))
      or ((c >= 'a') and (c <= 'f'))

  fun _is_unreserved(c: U8): Bool =>
    ((c >= 'A') and (c <= 'Z'))
      or ((c >= 'a') and (c <= 'z'))
      or ((c >= '0') and (c <= '9'))
      or (c == '-') or (c == '.') or (c == '_') or (c == '~')

  fun _is_sub_delim(c: U8): Bool =>
    (c == '!') or (c == '$') or (c == '&') or (c == '\'')
      or (c == '(') or (c == ')') or (c == '*') or (c == '+')
      or (c == ',') or (c == ';') or (c == '=')
