interface val _Version is (Equatable[Version] & Stringable)

primitive HTTP10 is _Version
  """HTTP/1.0 protocol version."""
  fun string(): String iso^ => "HTTP/1.0".clone()
  fun eq(that: Version): Bool => that is this

primitive HTTP11 is _Version
  """HTTP/1.1 protocol version."""
  fun string(): String iso^ => "HTTP/1.1".clone()
  fun eq(that: Version): Bool => that is this

type Version is ((HTTP10 | HTTP11) & _Version)
  """HTTP protocol version, either HTTP/1.0 or HTTP/1.1."""
