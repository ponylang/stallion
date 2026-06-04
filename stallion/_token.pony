primitive _Token
  """
  RFC 9110 §5.6.2 token: a non-empty sequence of `tchar`.

  ```
  tchar = "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" / "-" / "." /
          "^" / "_" / "`" / "|" / "~" / DIGIT / ALPHA
  ```

  Equivalently: visible ASCII (0x21–0x7E) excluding the delimiters
  `( ) < > @ , ; : \ " / [ ] ? = { }` (and, implicitly, SP/HTAB and control
  bytes, which fall outside 0x21–0x7E). This is the same set RFC 2616 calls a
  token, so cookie names (RFC 6265 §4.1.1, which defers to the RFC 2616 token)
  use it too.

  Single source for "what counts as a token character" across the parser
  (HTTP field names, RFC 9112 §5.1) and the cookie validator, mirroring how
  `_OWS` is the single source for optional whitespace.
  """

  fun apply(b: U8): Bool =>
    """Whether `b` is a `tchar` (a valid token character)."""
    if (b < 0x21) or (b > 0x7E) then return false end
    match b
    | '(' | ')' | '<' | '>' | '@'
    | ',' | ';' | ':' | '\\' | '"'
    | '/' | '[' | ']' | '?' | '='
    | '{' | '}' => false
    else
      true
    end

  fun valid(s: String box): Bool =>
    """Whether `s` is a non-empty token (`1*tchar`)."""
    if s.size() == 0 then return false end
    for b in s.values() do
      if not apply(b) then return false end
    end
    true
