use "pony_test"

class \nodoc\ iso _TestToken is UnitTest
  """
  Verify the `_Token` predicate and whole-string validity check against the
  RFC 9110 §5.6.2 `tchar` set and its boundaries.
  """
  fun name(): String => "token/predicate_and_valid"

  fun apply(h: TestHelper) =>
    // Representative tchar from the punctuation list, plus DIGIT and ALPHA.
    h.assert_true(_Token('!'), "! is tchar")
    h.assert_true(_Token('#'), "# is tchar")
    h.assert_true(_Token('$'), "$ is tchar")
    h.assert_true(_Token('%'), "% is tchar")
    h.assert_true(_Token('&'), "& is tchar")
    h.assert_true(_Token('\''), "apostrophe is tchar")
    h.assert_true(_Token('*'), "* is tchar")
    h.assert_true(_Token('+'), "+ is tchar")
    h.assert_true(_Token('-'), "- is tchar")
    h.assert_true(_Token('.'), ". is tchar")
    h.assert_true(_Token('^'), "^ is tchar")
    h.assert_true(_Token('_'), "_ is tchar")
    h.assert_true(_Token('`'), "backtick is tchar")
    h.assert_true(_Token('|'), "| is tchar")
    h.assert_true(_Token('~'), "~ is tchar")
    h.assert_true(_Token('0'), "digit is tchar")
    h.assert_true(_Token('9'), "digit is tchar")
    h.assert_true(_Token('A'), "uppercase letter is tchar")
    h.assert_true(_Token('z'), "lowercase letter is tchar")

    // Every RFC 9110 §5.6.2 delimiter is rejected.
    h.assert_false(_Token('('), "( is a delimiter")
    h.assert_false(_Token(')'), ") is a delimiter")
    h.assert_false(_Token('<'), "< is a delimiter")
    h.assert_false(_Token('>'), "> is a delimiter")
    h.assert_false(_Token('@'), "@ is a delimiter")
    h.assert_false(_Token(','), ", is a delimiter")
    h.assert_false(_Token(';'), "; is a delimiter")
    h.assert_false(_Token(':'), ": is a delimiter")
    h.assert_false(_Token('\\'), "backslash is a delimiter")
    h.assert_false(_Token('"'), "double quote is a delimiter")
    h.assert_false(_Token('/'), "/ is a delimiter")
    h.assert_false(_Token('['), "[ is a delimiter")
    h.assert_false(_Token(']'), "] is a delimiter")
    h.assert_false(_Token('?'), "? is a delimiter")
    h.assert_false(_Token('='), "= is a delimiter")
    h.assert_false(_Token('{'), "{ is a delimiter")
    h.assert_false(_Token('}'), "} is a delimiter")

    // Whitespace and control bytes are not tchar.
    h.assert_false(_Token(' '), "SP is not tchar")
    h.assert_false(_Token('\t'), "HTAB is not tchar")
    h.assert_false(_Token('\r'), "CR is not tchar")
    h.assert_false(_Token('\n'), "LF is not tchar")

    // Range boundaries: 0x20 (SP) just below, 0x21 (!) first, 0x7E (~)
    // last, 0x7F (DEL) just above, and 0xFF.
    h.assert_false(_Token(0x20), "0x20 is below the visible range")
    h.assert_true(_Token(0x21), "0x21 is the first visible char")
    h.assert_true(_Token(0x7E), "0x7E is the last visible char")
    h.assert_false(_Token(0x7F), "DEL is above the visible range")
    h.assert_false(_Token(0xFF), "0xFF is not tchar")

    // valid: non-empty 1*tchar, rejecting empty and any non-tchar byte.
    h.assert_true(_Token.valid("Content-Length"), "valid token name")
    h.assert_true(_Token.valid("X-Custom_Header"), "valid token name")
    h.assert_false(_Token.valid(""), "empty is not a token")
    h.assert_false(_Token.valid("Content-Length "), "trailing space")
    h.assert_false(_Token.valid("Content -Length"), "interior space")
    h.assert_false(_Token.valid("Foo@Bar"), "interior delimiter")
