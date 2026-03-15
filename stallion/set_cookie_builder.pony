class ref SetCookieBuilder
  """
  Build a validated `Set-Cookie` response header with secure defaults.

  Defaults: `Secure=true`, `HttpOnly=true`, `SameSite=Lax`. These defaults
  follow current security best practices — override them explicitly when
  needed.

  All `with_*` methods return `this` for chaining:

  ```pony
  match SetCookieBuilder("session", token)
    .with_path("/")
    .with_max_age(3600)
    .build()
  | let sc: SetCookie val =>
    // Use sc.header_value() with ResponseBuilder
  | let err: SetCookieBuildError =>
    // Handle validation error
  end
  ```

  `build()` validates the name, value, path, and domain, checks prefix rules
  (`__Host-`, `__Secure-`), and verifies `SameSite=None` + `Secure` consistency.
  Returns `SetCookie val` on success or `SetCookieBuildError` on failure.
  """
  let _name: String val
  let _value: String val
  var _path: (String val | None) = None
  var _domain: (String val | None) = None
  var _max_age: (I64 | None) = None
  var _expires: (I64 | None) = None
  var _secure: Bool = true
  var _http_only: Bool = true
  var _same_site: (SameSite | None) = SameSiteLax

  new create(name: String val, value: String val) =>
    """
    Create a builder for a `Set-Cookie` header with the given name and value.

    Defaults to `Secure`, `HttpOnly`, and `SameSite=Lax`.
    """
    _name = name
    _value = value

  fun ref with_path(path: String val): SetCookieBuilder ref =>
    """Set the `Path` attribute."""
    _path = path
    this

  fun ref with_domain(domain: String val): SetCookieBuilder ref =>
    """Set the `Domain` attribute."""
    _domain = domain
    this

  fun ref with_max_age(seconds: I64): SetCookieBuilder ref =>
    """Set the `Max-Age` attribute in seconds."""
    _max_age = seconds
    this

  fun ref with_expires(epoch_seconds: I64): SetCookieBuilder ref =>
    """Set the `Expires` attribute from epoch seconds."""
    _expires = epoch_seconds
    this

  fun ref with_secure(secure': Bool = true): SetCookieBuilder ref =>
    """Set or clear the `Secure` attribute."""
    _secure = secure'
    this

  fun ref with_http_only(http_only': Bool = true): SetCookieBuilder ref =>
    """Set or clear the `HttpOnly` attribute."""
    _http_only = http_only'
    this

  fun ref with_same_site(same_site: (SameSite | None)): SetCookieBuilder ref =>
    """
    Set the `SameSite` attribute.

    Pass a `SameSite` value to emit the attribute, or Pony's `None` to omit
    it entirely. Note that `SameSiteNone` emits `SameSite=None` (which
    requires `Secure`), while Pony's `None` omits the attribute.
    """
    _same_site = same_site
    this

  fun build(): (SetCookie val | SetCookieBuildError) =>
    """
    Validate and serialize the `Set-Cookie` header.

    Returns `SetCookie val` on success. Returns a `SetCookieBuildError`
    describing the first validation failure:
    - `InvalidCookieName` — name is not an RFC 2616 token
    - `InvalidCookieValue` — value contains non-cookie-octets
    - `InvalidCookiePath` — path contains CTLs or semicolons
    - `InvalidCookieDomain` — domain contains CTLs or semicolons
    - `CookiePrefixViolation` — `__Host-`/`__Secure-` prefix constraints
      not met
    - `SameSiteRequiresSecure` — `SameSite=None` without `Secure`
    """
    // Validate name
    if not _CookieValidator.valid_name(_name) then
      return InvalidCookieName
    end

    // Validate value
    if not _CookieValidator.valid_value(_value) then
      return InvalidCookieValue
    end

    // Validate path (no CTLs or semicolons per RFC 6265 §4.1.1)
    match _path
    | let p: String =>
      if not _CookieValidator.valid_attr_value(p) then
        return InvalidCookiePath
      end
    end

    // Validate domain (no CTLs or semicolons)
    match _domain
    | let d: String =>
      if not _CookieValidator.valid_attr_value(d) then
        return InvalidCookieDomain
      end
    end

    // Prefix rules
    if _name.compare_sub("__Host-", 7) is Equal then
      // __Host- requires: Secure, Path="/", no Domain
      if (not _secure)
        or (match _path | let p: String => p != "/" else true end)
        or (_domain isnt None)
      then
        return CookiePrefixViolation
      end
    elseif _name.compare_sub("__Secure-", 9) is Equal then
      // __Secure- requires: Secure
      if not _secure then
        return CookiePrefixViolation
      end
    end

    // SameSite=None requires Secure
    match _same_site
    | let _: SameSiteNone =>
      if not _secure then return SameSiteRequiresSecure end
    end

    // Serialize in fixed order:
    // name=value[; Path=...][; Domain=...][; Secure][; HttpOnly]
    //   [; SameSite=...][; Max-Age=...][; Expires=...]
    let header_value = recover val
      let buf = String
      buf.>append(_name)
        .>push('=')
        .>append(_value)

      match _path
      | let p: String => buf.>append("; Path=").>append(p)
      end

      match _domain
      | let d: String => buf.>append("; Domain=").>append(d)
      end

      if _secure then buf.append("; Secure") end
      if _http_only then buf.append("; HttpOnly") end

      match _same_site
      | let ss: SameSite =>
        buf.>append("; SameSite=").>append(ss.string())
      end

      match _max_age
      | let ma: I64 => buf.>append("; Max-Age=").>append(ma.string())
      end

      match _expires
      | let e: I64 => buf.>append("; Expires=").>append(_HTTPDate(e))
      end

      buf
    end

    SetCookie._create(_name, _value, header_value)
