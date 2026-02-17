class val URIAuthority is (Stringable & Equatable[URIAuthority])
  """
  A parsed URI authority component (RFC 3986 section 3.2).

  Format: `[userinfo@]host[:port]`

  The host may be empty — this occurs in URIs like `file:///path` where
  the authority is present (indicated by `//`) but contains no host.
  IP-literals (IPv6 and IPvFuture) include their brackets in the host
  string (e.g., `[::1]`).
  """
  let userinfo: (String | None)
  let host: String
  let port: (U16 | None)

  new val create(
    userinfo': (String | None),
    host': String,
    port': (U16 | None))
  =>
    userinfo = userinfo'
    host = host'
    port = port'

  fun string(): String iso^ =>
    let out = recover iso String end
    match userinfo
    | let u: String => out.append(u); out.push('@')
    end
    out.append(host)
    match port
    | let p: U16 => out.push(':'); out.append(p.string())
    end
    out

  fun eq(that: URIAuthority box): Bool =>
    let userinfo_eq =
      match (userinfo, that.userinfo)
      | (None, None) => true
      | (let a: String, let b: String) => a == b
      else
        false
      end
    let port_eq =
      match (port, that.port)
      | (None, None) => true
      | (let a: U16, let b: U16) => a == b
      else
        false
      end
    userinfo_eq and (host == that.host) and port_eq
