primitive _KeepAliveDecision
  """
  Determine whether to keep a connection alive based on HTTP version
  and the Connection header value.

  HTTP/1.1 defaults to keep-alive; HTTP/1.0 defaults to close. An explicit
  `Connection: close` or `Connection: keep-alive` header overrides the
  default.
  """

  fun apply(version: Version, connection: (String | None)): Bool =>
    match connection
    | let c: String =>
      let lower = c.lower()
      if lower == "close" then return false end
      if lower == "keep-alive" then return true end
    end
    // Default: HTTP/1.1 keeps alive, HTTP/1.0 does not
    version is HTTP11
