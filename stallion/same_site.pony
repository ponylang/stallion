interface val _SameSite is Stringable

primitive SameSiteStrict is _SameSite
  """The cookie is only sent with same-site requests."""
  fun string(): String iso^ => "Strict".clone()

primitive SameSiteLax is _SameSite
  """The cookie is sent with same-site requests and top-level navigations."""
  fun string(): String iso^ => "Lax".clone()

primitive SameSiteNone is _SameSite
  """The cookie is sent with all requests. Requires `Secure`."""
  fun string(): String iso^ => "None".clone()

// The SameSite attribute for Set-Cookie headers.
type SameSite is ((SameSiteStrict | SameSiteLax | SameSiteNone) & _SameSite)
