use "pony_test"
use uri_pkg = "uri"

class \nodoc\ iso _TestHostAuthorityMatch is UnitTest
  """
  Verify `_HostAuthorityMatch.valid` — agreement between a Host header value and
  a request-target authority (RFC 9110 §7.2).

  Covers case-insensitive host comparison, default-port normalization
  (http/https, including an uppercase scheme), exact-port matching when there is
  no scheme (CONNECT), IP-literals, IPv4-as-reg-name, userinfo exclusion, and
  the explicit non-normalization decisions (empty host, trailing dot,
  non-canonical IPv4, percent-encoding folded for case but never decoded).
  """
  fun name(): String => "host_authority/match"

  fun apply(h: TestHelper) =>
    // A typed `None` for the scheme argument (CONNECT / no scheme).
    let no_scheme: (String box | None) = None

    // --- reg-name, http default port ---------------------------------------
    h.assert_true(
      _HostAuthorityMatch.valid("example.com",
        uri_pkg.URIAuthority(None, "example.com", None), "http"),
      "reg-name, both portless, http")
    h.assert_true(
      _HostAuthorityMatch.valid("EXAMPLE.com",
        uri_pkg.URIAuthority(None, "example.com", None), "http"),
      "host comparison is case-insensitive")
    h.assert_false(
      _HostAuthorityMatch.valid("a.example",
        uri_pkg.URIAuthority(None, "b.example", None), "http"),
      "different hosts mismatch")

    // --- http default-port equivalence -------------------------------------
    h.assert_true(
      _HostAuthorityMatch.valid("example.com:80",
        uri_pkg.URIAuthority(None, "example.com", None), "http"),
      "Host :80 vs target no-port (http) match")
    h.assert_true(
      _HostAuthorityMatch.valid("example.com",
        uri_pkg.URIAuthority(None, "example.com", U16(80)), "http"),
      "Host no-port vs target :80 (http) match")
    h.assert_false(
      _HostAuthorityMatch.valid("example.com:8080",
        uri_pkg.URIAuthority(None, "example.com", None), "http"),
      "Host :8080 vs target default :80 mismatch")

    // --- https default port, uppercase scheme ------------------------------
    h.assert_true(
      _HostAuthorityMatch.valid("example.com:443",
        uri_pkg.URIAuthority(None, "example.com", None), "https"),
      "Host :443 vs target no-port (https) match")
    h.assert_true(
      _HostAuthorityMatch.valid("example.com:80",
        uri_pkg.URIAuthority(None, "example.com", None), "HTTP"),
      "scheme match is case-insensitive (HTTP -> 80)")

    // --- no scheme (CONNECT): exact port match -----------------------------
    h.assert_false(
      _HostAuthorityMatch.valid("example.com",
        uri_pkg.URIAuthority(None, "example.com", U16(443)), no_scheme),
      "no scheme: portless Host vs target :443 mismatch (no default)")
    h.assert_true(
      _HostAuthorityMatch.valid("example.com:443",
        uri_pkg.URIAuthority(None, "example.com", U16(443)), no_scheme),
      "no scheme: :443 vs :443 match")
    h.assert_true(
      _HostAuthorityMatch.valid("example.com",
        uri_pkg.URIAuthority(None, "example.com", None), no_scheme),
      "no scheme: both portless match (None == None)")

    // --- IP-literal --------------------------------------------------------
    h.assert_true(
      _HostAuthorityMatch.valid("[::1]",
        uri_pkg.URIAuthority(None, "[::1]", None), no_scheme),
      "IPv6 literal match")
    h.assert_true(
      _HostAuthorityMatch.valid("[2001:DB8::1]",
        uri_pkg.URIAuthority(None, "[2001:db8::1]", None), no_scheme),
      "IPv6 literal case-insensitive")
    h.assert_false(
      _HostAuthorityMatch.valid("[::1]",
        uri_pkg.URIAuthority(None, "[::2]", None), no_scheme),
      "IPv6 literal mismatch")

    // --- IPv4 is a reg-name; no IPv4 canonicalization ----------------------
    h.assert_true(
      _HostAuthorityMatch.valid("127.0.0.1",
        uri_pkg.URIAuthority(None, "127.0.0.1", None), no_scheme),
      "IPv4 match")
    h.assert_false(
      _HostAuthorityMatch.valid("127.0.0.1",
        uri_pkg.URIAuthority(None, "127.000.000.001", None), no_scheme),
      "IPv4 not canonicalized: leading zeros mismatch")

    // --- userinfo on the target is ignored ---------------------------------
    h.assert_true(
      _HostAuthorityMatch.valid("example.com:80",
        uri_pkg.URIAuthority("user", "example.com", U16(80)), "http"),
      "target userinfo is excluded from comparison")

    // --- empty port edge: empty port == no port, then default-normalized ---
    h.assert_true(
      _HostAuthorityMatch.valid("example.com:",
        uri_pkg.URIAuthority(None, "example.com", U16(80)), "http"),
      "empty Host port == no port, default-normalized to :80 (http)")

    // --- empty host is always a mismatch -----------------------------------
    h.assert_false(
      _HostAuthorityMatch.valid("",
        uri_pkg.URIAuthority(None, "example.com", None), "http"),
      "empty Host host mismatches non-empty target")
    h.assert_false(
      _HostAuthorityMatch.valid("example.com",
        uri_pkg.URIAuthority(None, "", None), "http"),
      "non-empty Host mismatches empty target host")
    h.assert_false(
      _HostAuthorityMatch.valid("",
        uri_pkg.URIAuthority(None, "", None), "http"),
      "two empty hosts still mismatch (no usable identity)")

    // --- trailing dot is not normalized ------------------------------------
    h.assert_false(
      _HostAuthorityMatch.valid("example.com.",
        uri_pkg.URIAuthority(None, "example.com", None), "http"),
      "trailing-dot FQDN not normalized")

    // --- percent-encoding: case folded, never decoded ----------------------
    h.assert_true(
      _HostAuthorityMatch.valid("a%2fb",
        uri_pkg.URIAuthority(None, "a%2Fb", None), no_scheme),
      "pct-encoded hex case folded (%2f == %2F)")
    h.assert_false(
      _HostAuthorityMatch.valid("a%2fb",
        uri_pkg.URIAuthority(None, "a/b", None), no_scheme),
      "pct-encoding never decoded (%2f != /)")
