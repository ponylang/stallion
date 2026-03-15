interface val _SetCookieBuildError is Stringable

primitive InvalidCookieName is _SetCookieBuildError
  """Cookie name contains invalid characters (not an RFC 2616 token)."""
  fun string(): String iso^ => "InvalidCookieName".clone()

primitive InvalidCookieValue is _SetCookieBuildError
  """Cookie value contains invalid characters (not RFC 6265 cookie-octets)."""
  fun string(): String iso^ => "InvalidCookieValue".clone()

primitive CookiePrefixViolation is _SetCookieBuildError
  """
  Cookie uses a `__Host-` or `__Secure-` prefix without meeting the required
  constraints (Secure flag, Path, Domain restrictions).
  """
  fun string(): String iso^ => "CookiePrefixViolation".clone()

primitive InvalidCookiePath is _SetCookieBuildError
  """Cookie path contains invalid characters (CTLs or semicolons)."""
  fun string(): String iso^ => "InvalidCookiePath".clone()

primitive InvalidCookieDomain is _SetCookieBuildError
  """Cookie domain contains invalid characters (CTLs or semicolons)."""
  fun string(): String iso^ => "InvalidCookieDomain".clone()

primitive SameSiteRequiresSecure is _SetCookieBuildError
  """`SameSite=None` requires the `Secure` attribute."""
  fun string(): String iso^ => "SameSiteRequiresSecure".clone()

// SetCookieBuildError union type alias.
type SetCookieBuildError is
  ((InvalidCookieName | InvalidCookieValue | InvalidCookiePath
  | InvalidCookieDomain | CookiePrefixViolation
  | SameSiteRequiresSecure) & _SetCookieBuildError)
