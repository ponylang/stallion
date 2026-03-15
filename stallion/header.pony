class val Header
  """
  A single HTTP header name-value pair.

  Used by `Headers.values()` to iterate over header entries. Names are
  lowercased by `Headers` on storage, so `name` will always be lowercase.
  """
  let name: String val
  let value: String val

  new val create(name': String val, value': String val) =>
    """Create a header with the given name and value."""
    name = name'
    value = value'
