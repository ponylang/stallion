trait ref HTTPServerLifecycleEventReceiver
  """
  HTTP request lifecycle callbacks delivered to the server actor.

  All callbacks have default no-op implementations. Override only the
  callbacks your actor needs. For most servers, `request_complete()` is
  the only required callback — it delivers the `Responder` for sending
  the response after the full request has been received. Override
  `request()` when you need to respond before the body arrives (e.g.,
  rejecting with 413) — it delivers the same `Responder` earlier.

  Callbacks are invoked synchronously inside the actor that owns the
  `HTTPServer`. The protocol class handles HTTP parsing and
  connection management internally, delivering only HTTP-level events
  through this interface.
  """

  fun ref request(request': Request val, responder: Responder) =>
    """
    Called when the request line and all headers have been parsed.

    The `Request` bundles method, URI, version, and headers into a single
    immutable value. The URI is a pre-parsed RFC 3986 structure — invalid
    URIs are rejected with 400 Bad Request before reaching this callback.

    The `responder` is specific to this request. Use `respond()` with a
    `ResponseBuilder`-constructed response, or use
    `start_chunked_response()`, `send_chunk()`, and `finish_response()`
    for streaming responses. The responder may be used immediately or
    stored for later use (e.g., after accumulating body chunks).
    """
    None

  fun ref body_chunk(data: Array[U8] val) =>
    """
    Called for each chunk of request body data as it arrives.

    Body data is delivered incrementally. Accumulate chunks manually if
    you need the complete body before responding.
    """
    None

  fun ref request_complete(request': Request val, responder: Responder) =>
    """
    Called when the entire request (including any body) has been received.

    The `request'` is the same instance delivered in `request()`. The
    `responder` is also the same instance. For most servers, this is the
    only callback needed — it delivers both the complete request metadata
    and the Responder for sending the response.
    """
    None

  fun ref closed() =>
    """
    Called when the connection closes.

    Fires on client disconnect, server-initiated close, or any other
    reason. Not called if the connection fails before starting.
    """
    None

  fun ref throttled() =>
    """
    Called when backpressure is applied on the connection.

    The TCP send buffer is full — stop generating response data until
    `unthrottled()` is called.
    """
    None

  fun ref unthrottled() =>
    """
    Called when backpressure is released on the connection.

    The TCP send buffer has drained — response generation may resume.
    """
    None
