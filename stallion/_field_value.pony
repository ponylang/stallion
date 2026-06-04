primitive _FieldValue
  """
  RFC 9110 §5.5 field-value validity.

  A field value containing CR, LF, or NUL is invalid: §5.5 requires a
  recipient to reject (or rewrite) such a message, "due to the varying ways
  that implementations might parse and interpret those characters." That
  variance is a request-smuggling vector — an intermediary that treats a bare
  CR or LF as a line terminator would see a header or message boundary where
  Stallion sees ordinary field-value bytes, desynchronizing the two.

  This checks exactly the §5.5 MUST-reject set (CR, LF, NUL). Other bytes —
  including SP, HTAB, and obs-text (0x80–0xFF) — are left to the value as-is;
  we reject what the RFC says to reject and no more.
  """

  fun forbidden(b: U8): Bool =>
    """Whether `b` is forbidden in a field value (CR, LF, or NUL)."""
    (b == '\r') or (b == '\n') or (b == 0)

  fun valid(s: String box): Bool =>
    """Whether `s` is free of the forbidden field-value bytes (CR, LF, NUL)."""
    for b in s.values() do
      if forbidden(b) then return false end
    end
    true
