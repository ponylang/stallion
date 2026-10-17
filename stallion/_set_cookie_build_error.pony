interface val _SetCookieBuildError
  fun string(): String val

primitive InvalidCookieName is _SetCookieBuildError
  """
  Cookie name contains invalid characters (not an RFC 2616 token).
  """
  fun string(): String val => "InvalidCookieName"

primitive InvalidCookieValue is _SetCookieBuildError
  """
  Cookie value contains invalid characters (not RFC 6265 cookie-octets).
  """
  fun string(): String val => "InvalidCookieValue"

primitive CookiePrefixViolation is _SetCookieBuildError
  """
  Cookie uses a `__Host-` or `__Secure-` prefix without meeting the required
  constraints (Secure flag, Path, Domain restrictions).
  """
  fun string(): String val => "CookiePrefixViolation"

primitive InvalidCookiePath is _SetCookieBuildError
  """
  Cookie path contains invalid characters (CTLs or semicolons).
  """
  fun string(): String val => "InvalidCookiePath"

primitive InvalidCookieDomain is _SetCookieBuildError
  """
  Cookie domain contains invalid characters (CTLs or semicolons).
  """
  fun string(): String val => "InvalidCookieDomain"

primitive SameSiteRequiresSecure is _SetCookieBuildError
  """
  `SameSite=None` requires the `Secure` attribute.
  """
  fun string(): String val => "SameSiteRequiresSecure"

// SetCookieBuildError union type alias.
type SetCookieBuildError is
  (
    ( InvalidCookieName
    | InvalidCookieValue
    | InvalidCookiePath
    | InvalidCookieDomain
    | CookiePrefixViolation
    | SameSiteRequiresSecure )
  & _SetCookieBuildError )
