trait ref Handler
  """
  Application handler for HTTP requests.

  All methods run synchronously inside the connection actor. Each request
  delivers a per-request `Responder` via `request_complete()` for sending
  responses.

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

  fun ref request_complete(responder: Responder)
    """
    Called when the entire request (including any body) has been received.

    The `responder` is specific to this request. Call `Responder.respond()`
    to send a complete response, or use `start_chunked_response()`,
    `send_chunk()`, and `finish_response()` for streaming responses. The
    handler may hold the responder and respond later (e.g., for deferred
    processing).
    """

  fun ref closed() =>
    """
    Called when the connection closes.

    Fires whenever the connection closes, whether due to client disconnect,
    server-initiated close (keep-alive=false, parse error, idle timeout),
    or any other reason. Not called if the connection fails before starting
    (i.e., before any handler methods have been called).
    """
    None

  fun ref throttled() =>
    """
    Called when backpressure is applied on the connection.

    The TCP send buffer is full — the handler should stop generating
    response data until `unthrottled` is called.
    """
    None

  fun ref unthrottled() =>
    """
    Called when backpressure is released on the connection.

    The TCP send buffer has drained — the handler may resume generating
    response data.
    """
    None

interface val HandlerFactory
  """
  Creates a handler for each new connection.

  The factory is `val` so it can be safely shared across connection actors.
  """
  fun apply(): Handler ref^
