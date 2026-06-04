primitive _QuotedSplit
  """
  Split a header field value on a delimiter byte, respecting quoted strings.

  HTTP list-valued fields (RFC 9110 §5.6.1) and parameterized fields separate
  elements with a delimiter — `,` between list members, `;` between
  parameters. A `quoted-string` parameter value (RFC 9110 §5.6.4) may itself
  contain that delimiter, so a naive byte split tears a legal value in half:
  `chunked;ext="a,b"` is one coding with one parameter, not two codings.

  This splitter tracks whether the scan is inside a double-quoted string and
  only treats a delimiter as a separator when it occurs outside one. Within a
  quoted string a `\` begins a `quoted-pair` (RFC 9110 §5.6.4): the next octet
  is literal data, so an escaped quote (`\"`) does not close the string and an
  escaped delimiter is not a separator.

  Segments are returned as zero-copy views, with the quotes, escapes, and any
  surrounding whitespace preserved — callers own trimming and normalization.
  An unterminated quoted string yields the remainder as a final segment rather
  than erroring; the second tuple element reports whether the scan ended
  inside an open quote, so a caller that needs to reject malformed input (the
  Transfer-Encoding framing path) can, while a lenient caller (Accept) ignores
  it.
  """

  fun apply(s: String val, delimiter: U8): (Array[String val] val, Bool) =>
    """
    Split `s` on `delimiter`, ignoring delimiters inside quoted strings.

    Returns the segments and `unterminated`: `true` when the scan ended inside
    an unclosed quoted string (the value is malformed).
    """
    let result = recover iso Array[String val] end
    var start: USize = 0
    var i: USize = 0
    var in_quotes: Bool = false
    let size = s.size()

    while i < size do
      try
        let b = s(i)?
        if in_quotes and (b == '\\') then
          // quoted-pair: skip the escaped octet so it can neither close the
          // quoted string nor act as a separator.
          i = i + 1
        elseif b == '"' then
          in_quotes = not in_quotes
        elseif (b == delimiter) and (not in_quotes) then
          result.push(s.trim(start, i))
          start = i + 1
        end
      end
      i = i + 1
    end
    result.push(s.trim(start, size))
    (consume result, in_quotes)
