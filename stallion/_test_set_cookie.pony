use "pony_check"
use "pony_test"

class \nodoc\ iso _TestSetCookieKnownGood is UnitTest
  """
  Verify exact output for known SetCookieBuilder configurations.
  """
  fun name(): String => "set_cookie/known_good"

  fun apply(h: TestHelper) =>
    _test_defaults(h)
    _test_all_attributes(h)
    _test_same_site_none(h)
    _test_same_site_strict(h)
    _test_no_secure(h)
    _test_no_http_only(h)
    _test_host_prefix(h)
    _test_secure_prefix(h)
    _test_omit_same_site(h)

  fun _test_defaults(h: TestHelper) =>
    match SetCookieBuilder("session", "abc123").build()
    | let sc: SetCookie val =>
      let hv = sc.header_value()
      h.assert_true(hv.contains("session=abc123"), "defaults: name=value")
      h.assert_true(hv.contains("Secure"), "defaults: Secure")
      h.assert_true(hv.contains("HttpOnly"), "defaults: HttpOnly")
      h.assert_true(hv.contains("SameSite=Lax"), "defaults: SameSite=Lax")
    | let e: SetCookieBuildError =>
      h.fail("defaults: unexpected error: " + e.string())
    end

  fun _test_all_attributes(h: TestHelper) =>
    match SetCookieBuilder("id", "xyz")
      .with_path("/app")
      .with_domain("example.com")
      .with_max_age(3600)
      .with_expires(0)
      .build()
    | let sc: SetCookie val =>
      let hv = sc.header_value()
      h.assert_true(hv.contains("id=xyz"), "all: name=value")
      h.assert_true(hv.contains("Path=/app"), "all: Path")
      h.assert_true(hv.contains("Domain=example.com"), "all: Domain")
      h.assert_true(hv.contains("Secure"), "all: Secure")
      h.assert_true(hv.contains("HttpOnly"), "all: HttpOnly")
      h.assert_true(hv.contains("SameSite=Lax"), "all: SameSite")
      h.assert_true(hv.contains("Max-Age=3600"), "all: Max-Age")
      h.assert_true(hv.contains("Expires=Thu, 01 Jan 1970 00:00:00 GMT"),
        "all: Expires")
      // Verify attribute order: name=value comes first
      try
        let nv_pos = hv.find("id=xyz")?
        let path_pos = hv.find("Path=")?
        let domain_pos = hv.find("Domain=")?
        let secure_pos = hv.find("; Secure")?
        let http_only_pos = hv.find("HttpOnly")?
        let same_site_pos = hv.find("SameSite=")?
        let max_age_pos = hv.find("Max-Age=")?
        let expires_pos = hv.find("Expires=")?
        h.assert_true(nv_pos < path_pos, "all: name=value before Path")
        h.assert_true(path_pos < domain_pos, "all: Path before Domain")
        h.assert_true(domain_pos < secure_pos, "all: Domain before Secure")
        h.assert_true(secure_pos < http_only_pos,
          "all: Secure before HttpOnly")
        h.assert_true(http_only_pos < same_site_pos,
          "all: HttpOnly before SameSite")
        h.assert_true(same_site_pos < max_age_pos,
          "all: SameSite before Max-Age")
        h.assert_true(max_age_pos < expires_pos,
          "all: Max-Age before Expires")
      else
        h.fail("all: could not find expected attributes in: " + hv)
      end
    | let e: SetCookieBuildError =>
      h.fail("all: unexpected error: " + e.string())
    end

  fun _test_same_site_none(h: TestHelper) =>
    match SetCookieBuilder("a", "b")
      .with_same_site(SameSiteNone)
      .build()
    | let sc: SetCookie val =>
      h.assert_true(sc.header_value().contains("SameSite=None"),
        "SameSite=None")
    | let e: SetCookieBuildError =>
      h.fail("SameSite=None: unexpected error: " + e.string())
    end

  fun _test_same_site_strict(h: TestHelper) =>
    match SetCookieBuilder("a", "b")
      .with_same_site(SameSiteStrict)
      .build()
    | let sc: SetCookie val =>
      h.assert_true(sc.header_value().contains("SameSite=Strict"),
        "SameSite=Strict")
    | let e: SetCookieBuildError =>
      h.fail("SameSite=Strict: unexpected error: " + e.string())
    end

  fun _test_no_secure(h: TestHelper) =>
    match SetCookieBuilder("a", "b")
      .with_secure(false)
      .with_same_site(SameSiteLax)
      .build()
    | let sc: SetCookie val =>
      h.assert_false(sc.header_value().contains("Secure"),
        "no secure: should not contain Secure")
    | let e: SetCookieBuildError =>
      h.fail("no secure: unexpected error: " + e.string())
    end

  fun _test_no_http_only(h: TestHelper) =>
    match SetCookieBuilder("a", "b")
      .with_http_only(false)
      .build()
    | let sc: SetCookie val =>
      h.assert_false(sc.header_value().contains("HttpOnly"),
        "no http_only: should not contain HttpOnly")
    | let e: SetCookieBuildError =>
      h.fail("no http_only: unexpected error: " + e.string())
    end

  fun _test_host_prefix(h: TestHelper) =>
    // Valid __Host- usage
    match SetCookieBuilder("__Host-session", "abc")
      .with_path("/")
      .build()
    | let sc: SetCookie val =>
      h.assert_true(sc.header_value().contains("__Host-session=abc"),
        "__Host-: valid")
    | let e: SetCookieBuildError =>
      h.fail("__Host-: unexpected error: " + e.string())
    end

    // Invalid: __Host- with Domain
    match SetCookieBuilder("__Host-session", "abc")
      .with_path("/")
      .with_domain("example.com")
      .build()
    | let sc: SetCookie val =>
      h.fail("__Host- with Domain: expected CookiePrefixViolation")
    | let e: CookiePrefixViolation => None // expected
    | let e: SetCookieBuildError =>
      h.fail("__Host- with Domain: expected CookiePrefixViolation, got "
        + e.string())
    end

    // Invalid: __Host- without Path="/"
    match SetCookieBuilder("__Host-session", "abc")
      .with_path("/app")
      .build()
    | let sc: SetCookie val =>
      h.fail("__Host- with Path=/app: expected CookiePrefixViolation")
    | let e: CookiePrefixViolation => None
    | let e: SetCookieBuildError =>
      h.fail("__Host- with Path=/app: expected CookiePrefixViolation, got "
        + e.string())
    end

    // Invalid: __Host- without Secure
    match SetCookieBuilder("__Host-session", "abc")
      .with_path("/")
      .with_secure(false)
      .build()
    | let sc: SetCookie val =>
      h.fail("__Host- without Secure: expected CookiePrefixViolation")
    | let e: CookiePrefixViolation => None
    | let e: SetCookieBuildError =>
      h.fail("__Host- without Secure: expected CookiePrefixViolation, got "
        + e.string())
    end

    // Invalid: __Host- without any Path set (defaults to None)
    match SetCookieBuilder("__Host-session", "abc").build()
    | let sc: SetCookie val =>
      h.fail("__Host- no path: expected CookiePrefixViolation")
    | let e: CookiePrefixViolation => None
    | let e: SetCookieBuildError =>
      h.fail("__Host- no path: expected CookiePrefixViolation, got "
        + e.string())
    end

  fun _test_secure_prefix(h: TestHelper) =>
    // Valid __Secure- usage
    match SetCookieBuilder("__Secure-token", "xyz").build()
    | let sc: SetCookie val =>
      h.assert_true(sc.header_value().contains("__Secure-token=xyz"),
        "__Secure-: valid")
    | let e: SetCookieBuildError =>
      h.fail("__Secure-: unexpected error: " + e.string())
    end

    // Invalid: __Secure- without Secure
    match SetCookieBuilder("__Secure-token", "xyz")
      .with_secure(false)
      .with_same_site(SameSiteLax)
      .build()
    | let sc: SetCookie val =>
      h.fail("__Secure- without Secure: expected CookiePrefixViolation")
    | let e: CookiePrefixViolation => None
    | let e: SetCookieBuildError =>
      h.fail("__Secure- without Secure: expected CookiePrefixViolation, got "
        + e.string())
    end

  fun _test_omit_same_site(h: TestHelper) =>
    match SetCookieBuilder("a", "b")
      .with_same_site(None)
      .build()
    | let sc: SetCookie val =>
      h.assert_false(sc.header_value().contains("SameSite"),
        "omit SameSite: should not contain SameSite")
    | let e: SetCookieBuildError =>
      h.fail("omit SameSite: unexpected error: " + e.string())
    end

class \nodoc\ iso _TestSetCookieErrors is UnitTest
  """
  Verify that invalid inputs produce the correct error types.
  """
  fun name(): String => "set_cookie/errors"

  fun apply(h: TestHelper) =>
    // Invalid name (contains space)
    match SetCookieBuilder("bad name", "ok").build()
    | let _: InvalidCookieName => None // expected
    | let sc: SetCookie val => h.fail("invalid name: expected error")
    | let e: SetCookieBuildError =>
      h.fail("invalid name: expected InvalidCookieName, got " + e.string())
    end

    // Invalid value (contains space)
    match SetCookieBuilder("ok", "bad value").build()
    | let _: InvalidCookieValue => None // expected
    | let sc: SetCookie val => h.fail("invalid value: expected error")
    | let e: SetCookieBuildError =>
      h.fail("invalid value: expected InvalidCookieValue, got " + e.string())
    end

    // Invalid path (semicolon injection)
    match SetCookieBuilder("ok", "ok")
      .with_path("/; Domain=.evil.com")
      .build()
    | let _: InvalidCookiePath => None // expected
    | let sc: SetCookie val => h.fail("invalid path: expected error")
    | let e: SetCookieBuildError =>
      h.fail("invalid path: expected InvalidCookiePath, got " + e.string())
    end

    // Invalid path (CRLF injection)
    match SetCookieBuilder("ok", "ok")
      .with_path("/\r\nEvil-Header: value")
      .build()
    | let _: InvalidCookiePath => None // expected
    | let sc: SetCookie val => h.fail("invalid path CRLF: expected error")
    | let e: SetCookieBuildError =>
      h.fail("invalid path CRLF: expected InvalidCookiePath, got "
        + e.string())
    end

    // Invalid domain (semicolon injection)
    match SetCookieBuilder("ok", "ok")
      .with_domain("evil.com; Path=/")
      .build()
    | let _: InvalidCookieDomain => None // expected
    | let sc: SetCookie val => h.fail("invalid domain: expected error")
    | let e: SetCookieBuildError =>
      h.fail("invalid domain: expected InvalidCookieDomain, got "
        + e.string())
    end

    // Invalid domain (control character)
    match SetCookieBuilder("ok", "ok")
      .with_domain("evil.com\x01")
      .build()
    | let _: InvalidCookieDomain => None // expected
    | let sc: SetCookie val => h.fail("invalid domain CTL: expected error")
    | let e: SetCookieBuildError =>
      h.fail("invalid domain CTL: expected InvalidCookieDomain, got "
        + e.string())
    end

    // SameSite=None without Secure
    match SetCookieBuilder("a", "b")
      .with_secure(false)
      .with_same_site(SameSiteNone)
      .build()
    | let _: SameSiteRequiresSecure => None // expected
    | let sc: SetCookie val =>
      h.fail("SameSite=None no Secure: expected error")
    | let e: SetCookieBuildError =>
      h.fail("SameSite=None no Secure: expected SameSiteRequiresSecure, got "
        + e.string())
    end

class \nodoc\ iso _PropertySetCookieValidBuild
  is Property1[(String val, String val)]
  """
  Valid names and values always build successfully.
  """
  fun name(): String => "set_cookie/valid_build"

  fun gen(): Generator[(String val, String val)] =>
    Generators.zip2[String val, String val](
      _CookieTestGenerators.valid_name(),
      _CookieTestGenerators.valid_value())

  fun ref property(
    arg1: (String val, String val),
    ph: PropertyHelper)
  =>
    (let n, let v) = arg1
    match SetCookieBuilder(n, v).build()
    | let sc: SetCookie val =>
      ph.assert_eq[String val](n, sc.name, "name matches")
      ph.assert_eq[String val](v, sc.value, "value matches")
      ph.assert_true(sc.header_value().contains(n + "=" + v),
        "header_value contains name=value")
    | let e: SetCookieBuildError =>
      ph.fail("Expected success for '" + n + "'='" + v +
        "', got: " + e.string())
    end

class \nodoc\ iso _PropertySetCookieInvalidNameErrors
  is Property1[String val]
  """
  Invalid names always produce InvalidCookieName.
  """
  fun name(): String => "set_cookie/invalid_name_errors"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.invalid_name()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    match SetCookieBuilder(arg1, "ok").build()
    | let _: InvalidCookieName => None // expected
    | let sc: SetCookie val =>
      ph.fail("Expected InvalidCookieName for '" + arg1 + "', got success")
    | let e: SetCookieBuildError =>
      ph.fail("Expected InvalidCookieName for '" + arg1 +
        "', got: " + e.string())
    end

class \nodoc\ iso _PropertySetCookieInvalidValueErrors
  is Property1[String val]
  """
  Invalid values always produce InvalidCookieValue.
  """
  fun name(): String => "set_cookie/invalid_value_errors"

  fun gen(): Generator[String val] =>
    _CookieTestGenerators.invalid_value()

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    match SetCookieBuilder("validname", arg1).build()
    | let _: InvalidCookieValue => None // expected
    | let sc: SetCookie val =>
      ph.fail("Expected InvalidCookieValue for '" + arg1 + "', got success")
    | let e: SetCookieBuildError =>
      ph.fail("Expected InvalidCookieValue for '" + arg1 +
        "', got: " + e.string())
    end
