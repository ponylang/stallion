use "pony_test"

class \nodoc\ iso _TestOWS is UnitTest
  """
  Verify the `_OWS` predicate, zero-copy trim, and strip-charset.
  """
  fun name(): String => "ows/predicate_and_trim"

  fun apply(h: TestHelper) =>
    // Predicate: only SP and HTAB are OWS.
    h.assert_true(_OWS(' '), "SP is OWS")
    h.assert_true(_OWS('\t'), "HTAB is OWS")
    h.assert_false(_OWS('a'), "letter is not OWS")
    h.assert_false(_OWS('\r'), "CR is not OWS")
    h.assert_false(_OWS('\n'), "LF is not OWS")
    h.assert_false(_OWS('\v'), "vertical tab is not OWS")
    h.assert_false(_OWS('\f'), "form feed is not OWS")
    h.assert_false(_OWS(0), "NUL is not OWS")
    h.assert_false(_OWS(0xFF), "0xFF is not OWS")

    // trim: leading, trailing, both, none, all-OWS, empty.
    h.assert_eq[String val]("x", _OWS.trim("  \tx"), "leading OWS")
    h.assert_eq[String val]("x", _OWS.trim("x\t  "), "trailing OWS")
    h.assert_eq[String val]("x y", _OWS.trim(" \tx y\t "), "both ends")
    h.assert_eq[String val]("x y", _OWS.trim("x y"), "no OWS")
    h.assert_eq[String val]("", _OWS.trim(" \t \t"), "all OWS")
    h.assert_eq[String val]("", _OWS.trim(""), "empty string")

    // trim does not touch interior OWS or non-OWS whitespace at the edges.
    h.assert_eq[String val]("a\tb", _OWS.trim(" a\tb "), "interior HTAB kept")
    h.assert_eq[String val]("\nx\n", _OWS.trim(" \nx\n "),
      "CR/LF are not trimmed")

    // trim returns a zero-copy view into the source — not a fresh
    // allocation. This is the reason the helper exists in this form
    // rather than cloning; a non-empty result must alias the source
    // buffer. Source has two leading OWS bytes, so the view starts at
    // offset 2.
    let src: String val = "  x y "
    h.assert_eq[USize](
      src.cpointer(2).usize(),
      _OWS.trim(src).cpointer().usize(),
      "trim returns a zero-copy view aliasing the source")

    // chars: the set passed to stdlib String.strip.
    h.assert_eq[String val](" \t", _OWS.chars(), "OWS charset")
