class val SetCookie
  """
  A validated, pre-serialized `Set-Cookie` response header.

  Created by `SetCookieBuilder.build()`. The `header_value()` method returns
  the complete header value string ready to be added to a response via
  `ResponseBuilder.add_header("Set-Cookie", set_cookie.header_value())`.
  """
  let name: String val
  let value: String val
  let _header_value: String val

  new val _create(
    name': String val,
    value': String val,
    header_value': String val)
  =>
    """Create a set-cookie. Package-private."""
    name = name'
    value = value'
    _header_value = header_value'

  fun header_value(): String val =>
    """
    Return the pre-serialized `Set-Cookie` header value.

    This is the complete string to use as the value of a `Set-Cookie`
    header, including all attributes.
    """
    _header_value
