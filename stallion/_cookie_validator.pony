primitive _CookieValidator
  """
  Validate cookie names and values per RFC 6265 and RFC 2616.

  Cookie names must be RFC 2616 tokens: ASCII 33–126 excluding
  separators `( ) < > @ , ; : \\ " / [ ] ? = { }`.

  Cookie values must be RFC 6265 cookie-octets: 0x21, 0x23–0x2B,
  0x2D–0x3A, 0x3C–0x5B, 0x5D–0x7E.
  """

  fun valid_name(name: String box): Bool =>
    """Return true if `name` is a valid cookie name (RFC 2616 token)."""
    _Token.valid(name)

  fun valid_value(value: String box): Bool =>
    """Return true if `value` contains only valid cookie-octets."""
    for byte in value.values() do
      if not _is_cookie_octet(byte) then return false end
    end
    true

  fun _is_cookie_octet(b: U8): Bool =>
    """
    RFC 6265 cookie-octet: 0x21, 0x23–0x2B, 0x2D–0x3A, 0x3C–0x5B, 0x5D–0x7E.
    """
    if b == 0x21 then return true end
    if (b >= 0x23) and (b <= 0x2B) then return true end
    if (b >= 0x2D) and (b <= 0x3A) then return true end
    if (b >= 0x3C) and (b <= 0x5B) then return true end
    if (b >= 0x5D) and (b <= 0x7E) then return true end
    false

  fun valid_attr_value(value: String box): Bool =>
    """
    Return true if `value` is safe as a Set-Cookie attribute value.

    RFC 6265 section 4.1.1 defines path-value as any US-ASCII character
    (0x20–0x7E) except semicolons. Control characters (0x00–0x1F, 0x7F)
    and non-ASCII bytes (0x80–0xFF) are rejected. The same constraint
    prevents attribute injection in domain values.
    """
    for byte in value.values() do
      if (byte < 0x20) or (byte > 0x7E) or (byte == ';') then
        return false
      end
    end
    true
