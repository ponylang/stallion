primitive _KeepAliveDecision
  """
  Determine whether to keep a connection alive based on HTTP version
  and the Connection header value.

  HTTP/1.1 defaults to keep-alive; HTTP/1.0 defaults to close. The
  `Connection` header is a comma-separated list of connection options
  (RFC 9110 §7.6.1). A `close` token anywhere in the list closes the
  connection and takes precedence over `keep-alive` (RFC 9112 §9.6); a
  `keep-alive` token keeps it alive. Tokens are matched exactly
  (case-insensitively) after stripping surrounding optional whitespace —
  never by substring.

  Repeated `Connection` header lines are combined into one value by
  `Headers.get` (RFC 9110 §5.3), so this handles both a single line with
  multiple tokens and multiple lines.
  """

  fun apply(version: Version, connection: (String | None)): Bool =>
    match connection
    | let c: String =>
      let options: Array[String] = c.split(",")
      var keep_alive = false
      for raw in options.values() do
        let token: String = _normalize(raw)
        if token == "close" then
          return false
        elseif token == "keep-alive" then
          keep_alive = true
        end
      end
      if keep_alive then return true end
    end
    // Default: HTTP/1.1 keeps alive, HTTP/1.0 does not
    version is HTTP11

  fun _normalize(raw: String box): String iso^ =>
    """
    Strip surrounding OWS from one connection option, then lowercase it.
    Mirrors `_TransferEncoding._normalize`; see the comment there on why two
    near-identical normalizers exist.
    """
    let token: String ref = raw.clone()
    token.strip(_OWS.chars())
    token.lower()
