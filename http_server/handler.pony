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
    send a response. After this method returns, the connection either
    stays open for the next request (HTTP/1.1 keep-alive) or closes
    (HTTP/1.0 default, or when the client sent `Connection: close`).
    """

  fun ref closed() =>
    """
    Called when the connection closes.

    This may fire during an idle keep-alive period (between requests),
    during request processing (if the client disconnects mid-request),
    or not at all (if the server initiates the close after a completed
    request/response cycle).
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
  Each call receives a `Responder` that the handler should store for
  sending responses.
  """
  fun apply(responder: Responder): Handler ref^
