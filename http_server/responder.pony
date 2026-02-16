use lori = "lori"

class ref Responder
  """
  Sends an HTTP response on a connection.

  The handler receives a `Responder` at creation time and calls `respond()`
  to send a response. Only the first call to `respond()` takes effect —
  subsequent calls are silently ignored.

  Responders are created internally by the connection actor. Application
  code should not attempt to construct them directly.
  """
  var _tcp_connection: lori.TCPConnection
  var _version: Version = HTTP11
  var _responded: Bool = false

  new _create(tcp_connection: lori.TCPConnection) =>
    """Create a responder for the given connection."""
    _tcp_connection = tcp_connection

  fun ref respond(
    status: Status,
    headers: (Headers val | None) = None,
    body: (ByteSeq | None) = None)
  =>
    """
    Send an HTTP response with the given status, headers, and optional body.

    Only the first call takes effect. The response version matches the
    request version (set internally by the connection actor).

    Pass `None` for headers to send a response with no custom headers.
    To include headers, create them in a `recover val` block:
    ```pony
    let headers = recover val
      let h = Headers
      h.set("Content-Type", "text/plain")
      h
    end
    responder.respond(StatusOK, headers, "Hello!")
    ```
    """
    if not _responded then
      _responded = true
      let h: Headers val = match headers
      | let h': Headers val => h'
      | None => recover val Headers end
      end
      let response = _ResponseSerializer(status, h, body, _version)
      match _tcp_connection.send(consume response)
      | let _: lori.SendError =>
        _tcp_connection.close()
      end
    end

  fun responded(): Bool =>
    """Whether a response has already been sent."""
    _responded

  fun ref _reset() =>
    """Reset for the next request on a keep-alive connection."""
    _responded = false

  fun ref _set_connection(tcp_connection: lori.TCPConnection) =>
    """Update the TCP connection (called by the connection after init)."""
    _tcp_connection = tcp_connection

  fun ref _set_version(version: Version) =>
    """Set the HTTP version for the response (called by the connection)."""
    _version = version
