trait ref Handler
  """
  Application handler for HTTP requests.

  All methods run synchronously inside the connection actor. The handler
  receives a `Responder` at creation time (via `HandlerFactory`) and uses
  it to send responses.

  Only `request_complete` must be implemented — the other methods have
  default no-op implementations for handlers that don't need them.
  """

  fun ref request(
    method: Method,
    uri: String val,
    version: Version,
    headers: Headers val)
  =>
    """
    Called when the request line and all headers have been parsed.

    For requests with a body, `body_chunk` calls follow. For requests
    without a body, `request_complete` is called immediately after.
    """
    None

  fun ref body_chunk(data: Array[U8] val) =>
    """
    Called for each chunk of request body data as it becomes available.

    Body data is delivered incrementally — not accumulated. Not all
    requests have bodies.
    """
    None

  fun ref request_complete()
    """
    Called when the entire request (including any body) has been received.

    This is typically where the handler calls `Responder.respond()` to
    send a response. After this method returns, the connection closes
    (Phase 3 — no keep-alive).
    """

  fun ref closed() =>
    """
    Called when the remote peer closes the connection before the request
    completes.

    Not called after a normal request/response cycle — once `request_complete`
    returns, the connection transitions to a closed state before lori's close
    notification arrives.
    """
    None

interface val HandlerFactory
  """
  Creates a handler for each new connection.

  The factory is `val` so it can be safely shared across connection actors.
  Each call receives a `Responder` that the handler should store for
  sending responses.
  """
  fun apply(responder: Responder): Handler ref^
