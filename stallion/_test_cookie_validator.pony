use "collections"
use "pony_check"

class \nodoc\ iso _PropertyValidCookieNameAccepted
  is Property1[String val]
  """
  Strings composed entirely of RFC 2616 token characters are valid
  cookie names.
  """
  fun name(): String => "cookie_validator/valid_name_accepted"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.valid_name()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    ph.assert_true(_CookieValidator.valid_name(arg1),
      "Expected valid name: " + arg1)

class \nodoc\ iso _PropertyInvalidCookieNameRejected
  is Property1[String val]
  """
  Strings containing at least one non-token character are rejected
  as cookie names.
  """
  fun name(): String => "cookie_validator/invalid_name_rejected"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.invalid_name()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    ph.assert_false(_CookieValidator.valid_name(arg1),
      "Expected invalid name: " + arg1)

class \nodoc\ iso _PropertyCookieNameBoundary
  is Property1[(String val, Bool)]
  """
  Mixed generator: valid names accepted, invalid names rejected.
  """
  fun name(): String => "cookie_validator/name_boundary"

  fun gen(): Generator[(String val, Bool)] =>
    _CookieTestGenerators.name_boundary()

  fun ref property(arg1: (String val, Bool), ph: PropertyHelper) =>
    (let s, let expect_valid) = arg1
    let result = _CookieValidator.valid_name(s)
    ph.assert_eq[Bool](expect_valid, result,
      "Name '" + s + "' expected " +
        if expect_valid then "valid" else "invalid" end)

class \nodoc\ iso _PropertyValidCookieValueAccepted
  is Property1[String val]
  """
  Strings composed entirely of RFC 6265 cookie-octets are valid
  cookie values.
  """
  fun name(): String => "cookie_validator/valid_value_accepted"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.valid_value()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    ph.assert_true(_CookieValidator.valid_value(arg1),
      "Expected valid value: " + arg1)

class \nodoc\ iso _PropertyInvalidCookieValueRejected
  is Property1[String val]
  """
  Strings containing at least one non-cookie-octet are rejected
  as cookie values.
  """
  fun name(): String => "cookie_validator/invalid_value_rejected"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.invalid_value()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    ph.assert_false(_CookieValidator.valid_value(arg1),
      "Expected invalid value: " + arg1)

class \nodoc\ iso _PropertyCookieValueBoundary
  is Property1[(String val, Bool)]
  """
  Mixed generator: valid values accepted, invalid values rejected.
  """
  fun name(): String => "cookie_validator/value_boundary"

  fun gen(): Generator[(String val, Bool)] =>
    _CookieTestGenerators.value_boundary()

  fun ref property(arg1: (String val, Bool), ph: PropertyHelper) =>
    (let s, let expect_valid) = arg1
    let result = _CookieValidator.valid_value(s)
    ph.assert_eq[Bool](expect_valid, result,
      "Value '" + s + "' expected " +
        if expect_valid then "valid" else "invalid" end)

class \nodoc\ iso _PropertyValidAttrValueAccepted
  is Property1[String val]
  """
  US-ASCII strings (0x20–0x7E) with no semicolons are valid attribute values.
  """
  fun name(): String => "cookie_validator/valid_attr_value_accepted"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.valid_attr_value()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    ph.assert_true(_CookieValidator.valid_attr_value(arg1),
      "Expected valid attr value: " + arg1)

class \nodoc\ iso _PropertyInvalidAttrValueRejected
  is Property1[String val]
  """
  Strings containing CTLs, non-ASCII bytes, or semicolons are rejected
  as attribute values.
  """
  fun name(): String => "cookie_validator/invalid_attr_value_rejected"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.invalid_attr_value()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    ph.assert_false(_CookieValidator.valid_attr_value(arg1),
      "Expected invalid attr value: " + arg1)

class \nodoc\ iso _PropertyAttrValueBoundary
  is Property1[(String val, Bool)]
  """
  Mixed generator: valid attr values accepted, invalid attr values rejected.
  """
  fun name(): String => "cookie_validator/attr_value_boundary"

  fun gen(): Generator[(String val, Bool)] =>
    _CookieTestGenerators.attr_value_boundary()

  fun ref property(arg1: (String val, Bool), ph: PropertyHelper) =>
    (let s, let expect_valid) = arg1
    let result = _CookieValidator.valid_attr_value(s)
    ph.assert_eq[Bool](expect_valid, result,
      "Attr value '" + s + "' expected " +
        if expect_valid then "valid" else "invalid" end)

primitive \nodoc\ _CookieTestGenerators
  """Generators derived from the same character sets the validator uses."""

  fun _token_chars(): String val =>
    """RFC 2616 token characters: ASCII 33-126 minus separators."""
    recover val
      let s = String
      var b: U8 = 33
      while b <= 126 do
        if _CookieValidator._is_token_char(b) then s.push(b) end
        b = b + 1
      end
      s
    end

  fun _cookie_octets(): String val =>
    """RFC 6265 cookie-octet characters."""
    recover val
      let s = String
      var b: U8 = 0
      while b < 255 do
        if _CookieValidator._is_cookie_octet(b) then s.push(b) end
        b = b + 1
      end
      if _CookieValidator._is_cookie_octet(255) then s.push(255) end
      s
    end

  fun valid_name(): Generator[String val] =>
    """Generate valid cookie names (1+ token chars)."""
    let chars = _token_chars()
    Generators.map2[USize, U64, String val](
      Generators.usize(1, 20),
      Generators.u64(),
      {(len: USize, seed: U64)(chars): String val =>
        recover val
          let s = String(len)
          var h: U64 = seed
          for i in Range(0, len) do
            h = (h * 6364136223846793005) + 1442695040888963407
            try s.push(chars((h.usize() >> 16) % chars.size())?) end
          end
          s
        end
      })

  fun invalid_name(): Generator[String val] =>
    """Generate invalid cookie names containing at least one non-token char."""
    Generators.frequency[String val]([
      as WeightedGenerator[String val]:
      // Empty string (always invalid)
      (1, Generators.repeatedly[String val]({(): String val^ => ""}))
      // Valid prefix + separator char + valid suffix
      (3, Generators.map2[USize, USize, String val](
        Generators.usize(0, 10),
        Generators.usize(0, 10),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('a') end
            s.push(' ') // space is a separator
            for i in Range(0, suffix_len) do s.push('b') end
            s
          end
        }))
      // Contains control character
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x01) // control character
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
      // Contains comma
      (1, Generators.repeatedly[String val](
        {(): String val^ => "name,bad"}))
      // Contains non-ASCII byte (0x80+)
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x80)
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
    ])

  fun name_boundary(): Generator[(String val, Bool)] =>
    """Mixed valid/invalid cookie names with expected validity."""
    Generators.frequency[(String val, Bool)]([
      as WeightedGenerator[(String val, Bool)]:
      (1, valid_name().map[(String val, Bool)](
        {(s: String val): (String val, Bool) => (s, true)}))
      (1, invalid_name().map[(String val, Bool)](
        {(s: String val): (String val, Bool) => (s, false)}))
    ])

  fun valid_value(): Generator[String val] =>
    """Generate valid cookie values (0+ cookie-octets)."""
    let chars = _cookie_octets()
    Generators.map2[USize, U64, String val](
      Generators.usize(0, 20),
      Generators.u64(),
      {(len: USize, seed: U64)(chars): String val =>
        recover val
          let s = String(len)
          var h: U64 = seed
          for i in Range(0, len) do
            h = (h * 6364136223846793005) + 1442695040888963407
            try s.push(chars((h.usize() >> 16) % chars.size())?) end
          end
          s
        end
      })

  fun invalid_value(): Generator[String val] =>
    """Generate invalid cookie values with at least one non-cookie-octet."""
    Generators.frequency[String val]([
      as WeightedGenerator[String val]:
      // Contains space (0x20)
      (2, Generators.map2[USize, USize, String val](
        Generators.usize(0, 10),
        Generators.usize(0, 10),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('a') end
            s.push(' ')
            for i in Range(0, suffix_len) do s.push('b') end
            s
          end
        }))
      // Contains double-quote (0x22)
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 10),
        Generators.usize(0, 10),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('a') end
            s.push('"')
            for i in Range(0, suffix_len) do s.push('b') end
            s
          end
        }))
      // Contains comma (0x2C)
      (1, Generators.repeatedly[String val](
        {(): String val^ => "value,bad"}))
      // Contains backslash (0x5C)
      (1, Generators.repeatedly[String val](
        {(): String val^ => "value\\bad"}))
      // Contains control character
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x01)
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
      // Contains DEL (0x7F)
      (1, Generators.repeatedly[String val](
        {(): String val^ => "value\x7Fbad"}))
      // Contains non-ASCII byte (0x80+)
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x80)
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
    ])

  fun value_boundary(): Generator[(String val, Bool)] =>
    """Mixed valid/invalid cookie values with expected validity."""
    Generators.frequency[(String val, Bool)]([
      as WeightedGenerator[(String val, Bool)]:
      (1, valid_value().map[(String val, Bool)](
        {(s: String val): (String val, Bool) => (s, true)}))
      (1, invalid_value().map[(String val, Bool)](
        {(s: String val): (String val, Bool) => (s, false)}))
    ])

  fun _attr_value_chars(): String val =>
    """Valid attribute value characters: 0x20–0x7E minus semicolon."""
    recover val
      let s = String
      var b: U8 = 0x20
      while b <= 0x7E do
        if b != ';' then s.push(b) end
        b = b + 1
      end
      s
    end

  fun valid_attr_value(): Generator[String val] =>
    """Generate valid attribute values (0+ safe chars, no CTLs or ';')."""
    let chars = _attr_value_chars()
    Generators.map2[USize, U64, String val](
      Generators.usize(0, 30),
      Generators.u64(),
      {(len: USize, seed: U64)(chars): String val =>
        recover val
          let s = String(len)
          var h: U64 = seed
          for i in Range(0, len) do
            h = (h * 6364136223846793005) + 1442695040888963407
            try s.push(chars((h.usize() >> 16) % chars.size())?) end
          end
          s
        end
      })

  fun invalid_attr_value(): Generator[String val] =>
    """Generate invalid attribute values with a CTL, non-ASCII byte, or ';'."""
    Generators.frequency[String val]([
      as WeightedGenerator[String val]:
      // Contains semicolon
      (2, Generators.map2[USize, USize, String val](
        Generators.usize(0, 10),
        Generators.usize(0, 10),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('a') end
            s.push(';')
            for i in Range(0, suffix_len) do s.push('b') end
            s
          end
        }))
      // Contains control character
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x01)
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
      // Contains DEL (0x7F)
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x7F)
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
      // Contains CRLF
      (1, Generators.repeatedly[String val](
        {(): String val^ => "/path\r\nHeader: evil"}))
      // Contains non-ASCII byte (0x80+)
      (1, Generators.map2[USize, USize, String val](
        Generators.usize(0, 5),
        Generators.usize(0, 5),
        {(prefix_len: USize, suffix_len: USize): String val =>
          recover val
            let s = String
            for i in Range(0, prefix_len) do s.push('x') end
            s.push(0x80)
            for i in Range(0, suffix_len) do s.push('y') end
            s
          end
        }))
    ])

  fun attr_value_boundary(): Generator[(String val, Bool)] =>
    """Mixed valid/invalid attribute values with expected validity."""
    Generators.frequency[(String val, Bool)]([
      as WeightedGenerator[(String val, Bool)]:
      (1, valid_attr_value().map[(String val, Bool)](
        {(s: String val): (String val, Bool) => (s, true)}))
      (1, invalid_attr_value().map[(String val, Bool)](
        {(s: String val): (String val, Bool) => (s, false)}))
    ])
