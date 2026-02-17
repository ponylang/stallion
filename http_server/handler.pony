type RequestBody is (Array[U8] val | None)
  """
  The complete request body delivered to a buffered `Handler`.

  `None` when the request had no body (including `Content-Length: 0`).
  """

trait ref Handler
  """
  Application handler for HTTP requests with buffered request bodies.

  The complete request body is delivered as a single value via
  `request_complete()`. This is the appropriate handler for most use cases
  (JSON APIs, form submissions, any endpoint that processes the complete body).

  Only `request_complete` must be implemented — the other methods have
  default no-op implementations for handlers that don't need them.
  """

  fun ref request(r: Request val) =>
    """
    Called when the request line and all headers have been parsed.

    The `Request` bundles method, URI, version, and headers into a single
    immutable value. Access components via `r.method`, `r.uri`,
    `r.version`, and `r.headers`.

    The URI is a pre-parsed RFC 3986 structure with components available
    directly (`r.uri.path`, `r.uri.query`, `r.uri.authority`, etc.). The
    connection layer parses the raw request-target before delivering it
    here — invalid URIs are rejected with 400 Bad Request before reaching
    the handler.

    For CONNECT requests, the URI has only the `authority` component
    populated (host and port); `path` is empty. Note that
    `r.uri.string()` reconstructs to `//host:port` rather than the
    wire-format `host:port`.

    For requests with a body, the body is buffered internally and
    delivered as a single `RequestBody` in `request_complete`. For
    requests without a body, `request_complete` receives `None`.
    """
    None

  fun ref request_complete(responder: Responder, body: RequestBody)
    """
    Called when the entire request (including any body) has been received.

    The `body` is the complete request body, or `None` if the request had
    no body (including `Content-Length: 0`). The body size is bounded by
    `max_body_size` in `ServerConfig` (default 1MB).

    The `responder` is specific to this request. Use `respond_raw()` with
    a `ResponseBuilder`-constructed response to send a complete response,
    or use `start_chunked_response()`, `send_chunk()`, and
    `finish_response()` for streaming responses. The handler may hold the
    responder and respond later (e.g., for deferred processing).
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
  Creates a buffered handler for each new connection.

  The factory is `val` so it can be safely shared across connection actors.
  """
  fun apply(): Handler ref^

trait ref StreamingHandler
  """
  Application handler for HTTP requests with streaming request bodies.

  Body data is delivered incrementally via `body_chunk()` as it arrives,
  rather than being buffered. Use this for large uploads, proxying, or
  any case where processing data incrementally is preferred over waiting
  for the complete body.

  Only `request_complete` must be implemented — the other methods have
  default no-op implementations for handlers that don't need them.
  """

  fun ref request(r: Request val) =>
    """
    Called when the request line and all headers have been parsed.

    The `Request` bundles method, URI, version, and headers into a single
    immutable value. Access components via `r.method`, `r.uri`,
    `r.version`, and `r.headers`.

    The URI is a pre-parsed RFC 3986 structure with components available
    directly (`r.uri.path`, `r.uri.query`, `r.uri.authority`, etc.). The
    connection layer parses the raw request-target before delivering it
    here — invalid URIs are rejected with 400 Bad Request before reaching
    the handler.

    For CONNECT requests, the URI has only the `authority` component
    populated (host and port); `path` is empty. Note that
    `r.uri.string()` reconstructs to `//host:port` rather than the
    wire-format `host:port`.

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

    The `responder` is specific to this request. Use `respond_raw()` with
    a `ResponseBuilder`-constructed response to send a complete response,
    or use `start_chunked_response()`, `send_chunk()`, and
    `finish_response()` for streaming responses. The handler may hold the
    responder and respond later (e.g., for deferred processing).
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

interface val StreamingHandlerFactory
  """
  Creates a streaming handler for each new connection.

  The factory is `val` so it can be safely shared across connection actors.
  """
  fun apply(): StreamingHandler ref^

type AnyHandlerFactory is (HandlerFactory | StreamingHandlerFactory)
  """
  Union of both handler factory types, accepted by `Server` and `_Connection`.
  """
