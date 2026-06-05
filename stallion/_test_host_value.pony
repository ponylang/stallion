use "pony_test"

class \nodoc\ iso _TestHostValue is UnitTest
  """
  Verify the `_HostValue` gate against the RFC 9110 §7.2 / RFC 9112 §3.2 Host
  value grammar (`uri-host [ ":" port ]`, uri-host per RFC 3986 §3.2.2).

  Each uri-host alternative (reg-name, IPv4, IP-literal) is checked both with
  and without a port, and the port itself is checked at its boundaries (empty,
  upper limit, over the limit, overflow, underscore).
  """
  fun name(): String => "host_value/valid"

  fun apply(h: TestHelper) =>
    // --- reg-name -----------------------------------------------------------
    h.assert_true(_HostValue.valid("example.com"), "reg-name")
    h.assert_true(_HostValue.valid("example.com:8080"), "reg-name + port")
    h.assert_true(_HostValue.valid("EXAMPLE.com"), "reg-name letters valid")
    h.assert_true(_HostValue.valid("sub.do-main.example"), "reg-name with -")
    h.assert_true(_HostValue.valid("a~b_c.d"), "reg-name unreserved set")
    h.assert_true(_HostValue.valid("a,b"), "comma is a sub-delim")
    h.assert_true(_HostValue.valid("a!$&'()*+;=b"), "full sub-delim set")
    h.assert_true(_HostValue.valid("a%41b"), "pct-encoded")
    h.assert_true(_HostValue.valid("%2F"), "pct-encoded only")
    h.assert_true(_HostValue.valid(""), "empty value (empty reg-name)")

    // IPv4 is a character-subset of reg-name; this gate validates syntax, not
    // IPv4 semantics, so a malformed-looking dotted value is a valid reg-name.
    h.assert_true(_HostValue.valid("127.0.0.1"), "IPv4")
    h.assert_true(_HostValue.valid("127.0.0.1:80"), "IPv4 + port")
    h.assert_true(_HostValue.valid("999.999.999.999"),
      "out-of-range IPv4 is a valid reg-name (no semantic IPv4 check)")

    // --- IP-literal ---------------------------------------------------------
    h.assert_true(_HostValue.valid("[::1]"), "IPv6 literal")
    h.assert_true(_HostValue.valid("[::1]:8080"), "IPv6 literal + port")
    h.assert_true(_HostValue.valid("[::1]:"), "IP-literal empty port")
    h.assert_true(_HostValue.valid("[::1]:65535"), "IP-literal port boundary")
    h.assert_true(_HostValue.valid("[2001:db8::1]"), "IPv6 literal")
    h.assert_true(_HostValue.valid("[::ffff:127.0.0.1]"), "IPv4-mapped IPv6")
    h.assert_true(_HostValue.valid("[v1.fe80::]"), "IPvFuture literal")

    // --- port boundaries ----------------------------------------------------
    h.assert_true(_HostValue.valid("host:"), "empty port is valid")
    h.assert_true(_HostValue.valid(":80"), "empty host with explicit port")
    h.assert_true(_HostValue.valid("host:0"), "port 0")
    h.assert_true(_HostValue.valid("host:65535"), "port upper boundary")
    h.assert_false(_HostValue.valid("host:65536"), "port over boundary")
    h.assert_false(_HostValue.valid("host:99999"), "port over boundary")
    h.assert_false(_HostValue.valid("host:99999999999999999999"),
      "port overflow rejected, not wrapped")
    h.assert_false(_HostValue.valid("host:6_5"),
      "underscore in port (read_int ignores it) rejected")
    h.assert_false(_HostValue.valid("host:80a"), "non-digit port")
    h.assert_false(_HostValue.valid("host:8:0"), "second colon in port")
    h.assert_false(_HostValue.valid("[::1]:8a"), "bad port after IP-literal")
    h.assert_false(_HostValue.valid("[::1]:65536"), "literal port over bound")

    // --- malformed hosts ----------------------------------------------------
    h.assert_false(_HostValue.valid("a, b"), "space is not a host char")
    h.assert_false(_HostValue.valid("host name"), "interior space")
    h.assert_false(_HostValue.valid("foo/bar"), "/ is a gen-delim")
    h.assert_false(_HostValue.valid("@host"), "@ is a gen-delim")
    h.assert_false(_HostValue.valid("user@host"), "userinfo not allowed")
    h.assert_false(_HostValue.valid("ho%st"), "incomplete pct-encoded")
    h.assert_false(_HostValue.valid("a%4"), "truncated pct-encoded")
    h.assert_false(_HostValue.valid("a%g0"), "non-hex pct-encoded")

    // --- malformed IP-literals ----------------------------------------------
    h.assert_false(_HostValue.valid("[::1"), "unterminated IP-literal")
    h.assert_false(_HostValue.valid("[::1]x"), "junk after IP-literal")
    h.assert_false(_HostValue.valid("[]"), "empty IP-literal")
    h.assert_false(_HostValue.valid("[xyz]"), "non-hex IPv6 literal")
    h.assert_false(_HostValue.valid("::1"), "unbracketed IPv6 rejected")
