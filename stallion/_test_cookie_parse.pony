use "collections"
use "pony_check"
use "pony_test"

class \nodoc\ iso _TestParseCookieKnownGood is UnitTest
  """
  Verify parsing of specific cookie header strings.
  """
  fun name(): String => "cookie_parse/known_good"

  fun apply(h: TestHelper) =>
    _test_single_cookie(h)
    _test_multiple_cookies(h)
    _test_missing_space_after_semicolon(h)
    _test_quoted_value(h)
    _test_equals_in_value(h)
    _test_empty_name_skipped(h)
    _test_no_equals_skipped(h)
    _test_whitespace_trimming(h)
    _test_empty_string(h)
    _test_from_headers_multiple(h)
    _test_case_sensitive_names(h)

  fun _test_single_cookie(h: TestHelper) =>
    let cookies = ParseCookies("session=abc123")
    h.assert_eq[USize](1, cookies.size(), "single: count")
    h.assert_eq[String val]("abc123",
      _get_or_empty(cookies, "session"),
      "single: value")

  fun _test_multiple_cookies(h: TestHelper) =>
    let cookies = ParseCookies("a=1; b=2; c=3")
    h.assert_eq[USize](3, cookies.size(), "multiple: count")
    h.assert_eq[String val]("1", _get_or_empty(cookies, "a"),
      "multiple: a")
    h.assert_eq[String val]("2", _get_or_empty(cookies, "b"),
      "multiple: b")
    h.assert_eq[String val]("3", _get_or_empty(cookies, "c"),
      "multiple: c")

  fun _test_missing_space_after_semicolon(h: TestHelper) =>
    let cookies = ParseCookies("a=1;b=2")
    h.assert_eq[USize](2, cookies.size(), "no space: count")
    h.assert_eq[String val]("1", _get_or_empty(cookies, "a"),
      "no space: a")
    h.assert_eq[String val]("2", _get_or_empty(cookies, "b"),
      "no space: b")

  fun _test_quoted_value(h: TestHelper) =>
    let cookies = ParseCookies("token=\"abc\"")
    h.assert_eq[String val]("abc", _get_or_empty(cookies, "token"),
      "quoted: value")

  fun _test_equals_in_value(h: TestHelper) =>
    let cookies = ParseCookies("data=a=b=c")
    h.assert_eq[String val]("a=b=c", _get_or_empty(cookies, "data"),
      "equals in value")

  fun _test_empty_name_skipped(h: TestHelper) =>
    let cookies = ParseCookies("=value; valid=ok")
    h.assert_eq[USize](1, cookies.size(), "empty name: count")
    h.assert_eq[String val]("ok", _get_or_empty(cookies, "valid"),
      "empty name: valid cookie")

  fun _test_no_equals_skipped(h: TestHelper) =>
    let cookies = ParseCookies("justname; valid=ok")
    h.assert_eq[USize](1, cookies.size(), "no equals: count")
    h.assert_eq[String val]("ok", _get_or_empty(cookies, "valid"),
      "no equals: valid cookie")

  fun _test_whitespace_trimming(h: TestHelper) =>
    let cookies = ParseCookies("  a  =  1  ;  b  =  2  ")
    h.assert_eq[USize](2, cookies.size(), "trimming: count")
    h.assert_eq[String val]("1", _get_or_empty(cookies, "a"),
      "trimming: a")
    h.assert_eq[String val]("2", _get_or_empty(cookies, "b"),
      "trimming: b")

  fun _test_empty_string(h: TestHelper) =>
    let cookies = ParseCookies("")
    h.assert_eq[USize](0, cookies.size(), "empty: count")

  fun _test_from_headers_multiple(h: TestHelper) =>
    let headers = recover val
      let h' = Headers
      h'.add("cookie", "a=1; b=2")
      h'.add("cookie", "c=3")
      h'.add("content-type", "text/html")
      h'
    end
    let cookies = ParseCookies.from_headers(headers)
    h.assert_eq[USize](3, cookies.size(), "from_headers: count")
    h.assert_eq[String val]("1", _get_or_empty(cookies, "a"),
      "from_headers: a")
    h.assert_eq[String val]("2", _get_or_empty(cookies, "b"),
      "from_headers: b")
    h.assert_eq[String val]("3", _get_or_empty(cookies, "c"),
      "from_headers: c")

  fun _test_case_sensitive_names(h: TestHelper) =>
    let cookies = ParseCookies("Name=upper; name=lower")
    h.assert_eq[USize](2, cookies.size(), "case: count")
    h.assert_eq[String val]("upper", _get_or_empty(cookies, "Name"),
      "case: Name")
    h.assert_eq[String val]("lower", _get_or_empty(cookies, "name"),
      "case: name")

  fun _get_or_empty(cookies: RequestCookies val, n: String): String val =>
    match cookies.get(n)
    | let v: String val => v
    else ""
    end

class \nodoc\ iso _PropertyCookieParseRoundtrip
  is Property1[Array[(String val, String val)] ref]
  """
  Generate valid cookie pairs, serialize as a Cookie header, parse back,
  and verify all pairs are present with correct values.
  """
  fun name(): String => "cookie_parse/roundtrip"

  fun gen(): Generator[Array[(String val, String val)] ref] =>
    let pair_gen = Generators.zip2[String val, String val](
      _CookieTestGenerators.valid_name(),
      _CookieTestGenerators.valid_value())
    Generators.array_of[(String val, String val)](pair_gen, 1, 5)

  fun ref property(
    arg1: Array[(String val, String val)] ref,
    ph: PropertyHelper)
  =>
    // Deduplicate: keep first occurrence of each name (matches get() semantics)
    let seen = Map[String val, String val]
    let unique = Array[(String val, String val)]
    for (n, v) in arg1.values() do
      if not seen.contains(n) then
        seen(n) = v
        unique.push((n, v))
      end
    end

    // Serialize as a Cookie header value
    var header_value: String val = ""
    var first = true
    for (n, v) in unique.values() do
      if not first then header_value = header_value + "; " end
      header_value = header_value + n + "=" + v
      first = false
    end

    // Parse
    let cookies = ParseCookies(header_value)

    // Verify each pair is present
    for (n, v) in unique.values() do
      let got = match cookies.get(n)
      | let s: String val => s
      else ""
      end
      ph.assert_eq[String val](v, got,
        "Cookie '" + n + "' expected '" + v + "' got '" + got + "'")
    end

class \nodoc\ iso _PropertyCookieParseRobustness
  is Property1[String val]
  """
  Arbitrary strings never crash the parser.
  """
  fun name(): String => "cookie_parse/robustness"

  fun gen(): Generator[String val] =>
    Generators.ascii_printable(0, 100)

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    // This should never crash — just call it
    let cookies = ParseCookies(arg1)
    // size() should return a non-negative value (always true for USize)
    ph.assert_true(cookies.size() <= arg1.size(),
      "Cookie count should not exceed input length")
