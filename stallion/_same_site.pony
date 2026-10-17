interface val _SameSite
  fun string(): String val

primitive SameSiteStrict is _SameSite
  """
  The cookie is only sent with same-site requests.
  """
  fun string(): String val => "Strict"

primitive SameSiteLax is _SameSite
  """
  The cookie is sent with same-site requests and top-level navigations.
  """
  fun string(): String val => "Lax"

primitive SameSiteNone is _SameSite
  """
  The cookie is sent with all requests. Requires `Secure`.
  """
  fun string(): String val => "None"

// The SameSite attribute for Set-Cookie headers.
type SameSite is ((SameSiteStrict | SameSiteLax | SameSiteNone) & _SameSite)
