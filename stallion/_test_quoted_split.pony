use "pony_test"

class \nodoc\ iso _TestQuotedSplit is UnitTest
  """
  Verify `_QuotedSplit` splits on a delimiter while treating quoted strings
  (including `quoted-pair` backslash escapes) as opaque.
  """
  fun name(): String => "quoted_split/split"

  fun apply(h: TestHelper) =>
    // Plain splitting on each delimiter the package uses. `false` = the
    // value's quotes are balanced (not unterminated).
    _check(h, "a,b,c", ',', [as String val: "a"; "b"; "c"], false)
    _check(h, "a;b;c", ';', [as String val: "a"; "b"; "c"], false)

    // A delimiter inside a quoted string is not a separator. The quotes are
    // preserved — callers do their own stripping.
    _check(h, "a,\"b,c\",d", ',', [as String val: "a"; "\"b,c\""; "d"], false)
    _check(h, "a;\"b;c\";d", ';', [as String val: "a"; "\"b;c\""; "d"], false)

    // quoted-pair: an escaped quote does not close the string, so a comma
    // that follows inside the same quoted string stays attached. Without
    // escape handling, `ext="a\",b"` would split into `ext="a\"` and `b"`.
    _check(h, "ext=\"a\\\",b\"", ',', [as String val: "ext=\"a\\\",b\""],
      false)

    // quoted-pair, opposite direction: the escaped quote keeps the real
    // closing quote from being mistaken for a re-open, so the trailing comma
    // does split. Without escape handling this collapses to one segment.
    _check(h, "x=\"a\\\"b\",y", ',',
      [as String val: "x=\"a\\\"b\""; "y"], false)

    // Edges: empty input, leading/trailing/consecutive delimiters all yield
    // empty segments (the caller decides whether to drop them).
    _check(h, "", ',', [as String val: ""], false)
    _check(h, ",a", ',', [as String val: ""; "a"], false)
    _check(h, "a,", ',', [as String val: "a"; ""], false)
    _check(h, "a,,b", ',', [as String val: "a"; ""; "b"], false)

    // Unterminated quoted strings swallow the rest of the value rather than
    // erroring, and report `unterminated = true` so a strict caller can
    // reject. A trailing backslash inside the open quote is handled safely.
    _check(h, "\"a,b", ',', [as String val: "\"a,b"], true)
    _check(h, "a,\"b", ',', [as String val: "a"; "\"b"], true)
    _check(h, "\"a\\", ',', [as String val: "\"a\\"], true)

  fun _check(h: TestHelper, s: String val, delimiter: U8,
    expected: Array[String val] box, unterminated: Bool)
  =>
    (let actual, let ended_open) = _QuotedSplit(s, delimiter)
    h.assert_eq[Bool](unterminated, ended_open,
      "unterminated flag for \"" + s + "\"")
    h.assert_eq[USize](expected.size(), actual.size(),
      "segment count for \"" + s + "\"")
    var i: USize = 0
    while i < expected.size() do
      try
        h.assert_eq[String val](expected(i)?, actual(i)?,
          "segment " + i.string() + " of \"" + s + "\"")
      end
      i = i + 1
    end
