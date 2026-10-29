interface val _SetCookieBuildError
  fun string(): String

primitive InvalidCookieName is _SetCookieBuildError
  """
  Cookie name contains invalid characters (not an RFC 2616 token).
  """
  fun string(): String => "InvalidCookieName"

primitive InvalidCookieValue is _SetCookieBuildError
  """
  Cookie value contains invalid characters (not RFC 6265 cookie-octets).
  """
  fun string(): String => "InvalidCookieValue"

primitive CookiePrefixViolation is _SetCookieBuildError
  """
  Cookie uses a `__Host-` or `__Secure-` prefix without meeting the required
  constraints (Secure flag, Path, Domain restrictions).
  """
  fun string(): String => "CookiePrefixViolation"

primitive InvalidCookiePath is _SetCookieBuildError
  """
  Cookie path contains invalid characters (CTLs or semicolons).
  """
  fun string(): String => "InvalidCookiePath"

primitive InvalidCookieDomain is _SetCookieBuildError
  """
  Cookie domain contains invalid characters (CTLs or semicolons).
  """
  fun string(): String => "InvalidCookieDomain"

primitive SameSiteRequiresSecure is _SetCookieBuildError
  """
  `SameSite=None` requires the `Secure` attribute.
  """
  fun string(): String => "SameSiteRequiresSecure"

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
