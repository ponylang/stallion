primitive _OWS
  """
  RFC 9110 §5.6.3 optional whitespace (OWS): only SP and HTAB.

  Single source for "what counts as OWS" across the parser and the
  list-field handlers, in the three forms the code actually needs: a byte
  predicate, a zero-copy trim over a `String val`, and the character set
  for stdlib `String.strip`.

  This is OWS specifically — SP *or* HTAB. The request line's mandatory
  single-SP delimiters (RFC 9112 §3) are a different thing and must not
  use this; a delimiter that accepted HTAB would be wrong.
  """

  fun apply(b: U8): Bool =>
    """Whether `b` is an OWS byte (SP or HTAB)."""
    (b == ' ') or (b == '\t')

  fun trim(s: String val): String val =>
    """
    Return `s` with leading and trailing OWS removed, as a zero-copy view
    (no allocation).
    """
    var first: USize = 0
    var last: USize = s.size()
    while (first < last) and try apply(s(first)?) else false end do
      first = first + 1
    end
    while (last > first) and try apply(s(last - 1)?) else false end do
      last = last - 1
    end
    s.trim(first, last)

  fun chars(): String =>
    """The OWS character set, for use with stdlib `String.strip`."""
    " \t"
