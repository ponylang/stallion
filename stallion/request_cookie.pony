class val RequestCookie
  """
  A single name-value pair parsed from a `Cookie` request header.

  Created internally by `ParseCookies`. Use `RequestCookies.values()` to
  iterate over parsed cookies, or `RequestCookies.get()` to look up a
  cookie by name.
  """
  let name: String val
  let value: String val

  new val _create(name': String val, value': String val) =>
    """Create a request cookie. Package-private."""
    name = name'
    value = value'
