use "pony_test"

class \nodoc\ iso _TestFieldValue is UnitTest
  """
  Verify the `_FieldValue` forbidden-byte predicate and whole-string check
  against the RFC 9110 §5.5 MUST-reject set (CR, LF, NUL).
  """
  fun name(): String => "field_value/forbidden_and_valid"

  fun apply(h: TestHelper) =>
    // The three forbidden bytes.
    h.assert_true(_FieldValue.forbidden('\r'), "CR is forbidden")
    h.assert_true(_FieldValue.forbidden('\n'), "LF is forbidden")
    h.assert_true(_FieldValue.forbidden(0), "NUL is forbidden")

    // Bytes that are allowed in a field value: SP, HTAB, visible ASCII,
    // and obs-text (0x80–0xFF) are not forbidden.
    h.assert_false(_FieldValue.forbidden(' '), "SP is allowed")
    h.assert_false(_FieldValue.forbidden('\t'), "HTAB is allowed")
    h.assert_false(_FieldValue.forbidden('a'), "letter is allowed")
    h.assert_false(_FieldValue.forbidden('0'), "digit is allowed")
    h.assert_false(_FieldValue.forbidden(0x7F), "DEL is not in the set")
    h.assert_false(_FieldValue.forbidden(0x80), "obs-text is allowed")
    h.assert_false(_FieldValue.forbidden(0xFF), "obs-text is allowed")

    // valid: rejects any string containing a forbidden byte, accepts the
    // rest. Empty is valid (a field value may be empty).
    h.assert_true(_FieldValue.valid(""), "empty value is valid")
    h.assert_true(_FieldValue.valid("application/json"), "plain value")
    h.assert_true(_FieldValue.valid("a b\tc"), "interior SP and HTAB")
    h.assert_false(_FieldValue.valid("a\rb"), "interior CR")
    h.assert_false(_FieldValue.valid("a\nb"), "interior LF")
    h.assert_false(_FieldValue.valid(recover val String.>push(0) end),
      "interior NUL")
