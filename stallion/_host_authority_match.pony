use uri_pkg = "uri"

primitive _HostAuthorityMatch
  """
  RFC 9110 §7.2 Host / request-target authority agreement.

  When the request-target carries its own authority (absolute-form, or the
  authority-form used by CONNECT), RFC 9110 §7.2 requires the client to send a
  `Host` field value identical to that authority, excluding any userinfo. A
  request that presents two *disagreeing* host identities — one in the
  request-target authority, one in `Host` — is a routing-confusion /
  request-smuggling surface ("Host of Troubles"): a front-end and an origin
  (or an origin and the application atop it) can route or authorize on different
  identities and be desynchronized. No conformant client sends a disagreeing
  pair, so the protocol layer rejects the mismatch with 400.

  `valid` answers "does the Host value agree with the target authority?" It is
  a pure comparator; the decision of *when* to call it (only when a Host is
  present and the target has an authority) lives in
  `HTTPServer.request_received`, and the separate CONNECT-port requirement is
  enforced there too — this primitive never needs to know about CONNECT.

  Equivalence rules (no semantic normalization beyond ASCII case):

  * **Userinfo** is excluded. The Host value can never carry userinfo
    (`_HostValue` rejects `@`); only the target operand can, and it is dropped
    before comparing.
  * **Host** is compared case-insensitively (ASCII), per RFC 3986 §6.2.2.1.
    IP-literal brackets are part of the host string on both sides and compare
    literally. The case fold also makes the hex digits of a percent-encoded
    octet in a reg-name case-insensitive (`%2f` == `%2F`), but nothing is ever
    *decoded* (`%2f` != `/`), consistent with the never-decode doctrine.
    (IP-literals cannot contain `%` under the IPv6/IPvFuture grammar, so pct-hex
    folding only ever applies to reg-names.) No further normalization: a
    trailing-dot FQDN (`example.com.`), a non-canonical IPv4
    (`127.000.000.001`), or any other surface-different host is treated as
    disagreeing — the conservative direction, since downstream routers commonly
    treat such variants differently, which is the very desync this guards
    against.
  * **Empty host** on either side is a mismatch: an authority with no host, or a
    `Host` with no host, presents no usable identity to agree on.
  * **Port** is compared after default-port normalization. The default is
    derived from the target's scheme (matched case-insensitively, since
    `ParseURI` keeps the scheme verbatim): `http` -> 80, `https` -> 443; any
    other scheme, or no scheme (CONNECT), has no default. Each side's effective
    port is its explicit port if present, else the default (which may be
    absent). They match when the effective ports are equal — so `example.com`
    and `example.com:80` agree for `http`, symmetrically.

  Implementation note: the Host value is re-parsed with
  `uri_pkg.ParseURIAuthority` to split host from port. This is sound because
  `request_received` only calls `valid` after `_HostValue.valid` has accepted
  the value, and
  `ParseURIAuthority` accepts every `_HostValue`-valid host (it is strictly more
  lenient on reg-name and equally strict on the port bound — see the
  mirrored-predicates note in `_host_value.pony`). A parse failure is therefore
  unreachable for a valid input; should one somehow occur, returning `false`
  (reject) is the safe direction.
  """
  fun valid(
    host_value: String val,
    target: uri_pkg.URIAuthority box,
    scheme: (String box | None))
    : Bool
  =>
    let host_auth =
      match uri_pkg.ParseURIAuthority(host_value)
      | let a: uri_pkg.URIAuthority val => a
      | let _: uri_pkg.URIParseError val => return false
      end

    // Userinfo is dropped: neither side's userinfo participates in the match.
    let h_host = host_auth.host
    let t_host = target.host
    if (h_host.size() == 0) or (t_host.size() == 0) then
      return false
    end
    if not _ascii_ci_eq(h_host, t_host) then
      return false
    end

    let default = _default_port(scheme)
    match (_resolve_port(host_auth.port, default),
      _resolve_port(target.port, default))
    | (None, None) => true
    | (let a: U16, let b: U16) => a == b
    else
      false
    end

  fun _resolve_port(port: (U16 | None), default: (U16 | None))
    : (U16 | None)
  =>
    """The explicit port if present, otherwise the scheme default."""
    match port
    | let p: U16 => p
    | None => default
    end

  fun _default_port(scheme: (String box | None)): (U16 | None) =>
    """The default port for a scheme: http -> 80, https -> 443, else none."""
    match scheme
    | let s: String box =>
      if _ascii_ci_eq(s, "http") then
        U16(80)
      elseif _ascii_ci_eq(s, "https") then
        U16(443)
      else
        None
      end
    | None => None
    end

  fun _ascii_ci_eq(a: String box, b: String box): Bool =>
    """Case-insensitive (ASCII) byte-wise string equality."""
    if a.size() != b.size() then
      return false
    end
    try
      var i: USize = 0
      while i < a.size() do
        if _lower(a(i)?) != _lower(b(i)?) then
          return false
        end
        i = i + 1
      end
      true
    else
      _Unreachable()
      false
    end

  fun _lower(c: U8): U8 =>
    if (c >= 'A') and (c <= 'Z') then c + 32 else c end
