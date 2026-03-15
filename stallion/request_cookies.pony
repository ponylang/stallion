class val RequestCookies
  """
  An immutable collection of cookies parsed from request `Cookie` headers.

  Use `get()` to look up a cookie value by name (case-sensitive, returns
  the first match) or `values()` to iterate over all parsed cookies.

  Created by `ParseCookies` — application code does not construct this
  directly.
  """
  let _cookies: Array[RequestCookie val] val

  new val _create(cookies: Array[RequestCookie val] val) =>
    """Create a cookie collection. Package-private."""
    _cookies = cookies

  fun get(name: String): (String val | None) =>
    """
    Get the value of the first cookie with the given name (case-sensitive).

    Returns `None` if no cookie with that name exists.
    """
    for cookie in _cookies.values() do
      if cookie.name == name then return cookie.value end
    end
    None

  fun values(): ArrayValues[RequestCookie val,
    Array[RequestCookie val] val]
  =>
    """Iterate over all parsed cookies."""
    _cookies.values()

  fun size(): USize =>
    """Return the number of parsed cookies."""
    _cookies.size()
