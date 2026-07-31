use lori = "lori"

trait ref HTTPServerLifecycleEventReceiver
  """
  HTTP request lifecycle callbacks delivered to the server actor.

  All callbacks have default no-op implementations. Override only the
  callbacks your actor needs. For most servers, `on_request_complete()` is
  the only required callback — it delivers the `Responder` for sending
  the response after the full request has been received. Override
  `on_request()` when you need to respond before the body arrives (e.g.,
  rejecting with 413) — it delivers the same `Responder` earlier.

  Callbacks are invoked synchronously inside the actor that owns the
  `HTTPServer`. The protocol class handles HTTP parsing and
  connection management internally, delivering only HTTP-level events
  through this interface.
  """

  fun ref on_request(request': Request val, responder: Responder) =>
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

  fun ref on_body_chunk(data: Array[U8] val) =>
    """
    Called for each chunk of request body data as it arrives.

    Body data is delivered incrementally. Accumulate chunks manually if
    you need the complete body before responding.
    """
    None

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    """
    Called when the entire request (including any body) has been received.

    The `request'` is the same instance delivered in `on_request()`. The
    `responder` is also the same instance. For most servers, this is the
    only callback needed — it delivers both the complete request metadata
    and the Responder for sending the response.
    """
    None

  fun ref on_closed() =>
    """
    Called once the connection is closed.

    Fires on client disconnect, server-initiated close, or any other
    reason. Not called if the connection fails before starting — see
    `on_start_failure()` for that case.

    When the server closes first — through `HTTPServer.close()` or any
    other close stallion starts — a close taken while the connection is
    under backpressure (from `on_throttled()` until `on_unthrottled()`)
    is a hard close: it shuts the connection down at once, drops
    undelivered data, and fires this callback in the same turn. A close
    taken at any other time leaves the connection open until the peer
    closes its half, and this callback fires then. Stallion sets no
    limit on how long that takes, so an actor that releases resources
    here holds them until the peer closes.

    To close without waiting on the peer, call `dispose()` on the actor:
    `HTTPServerActor` is a `lori.TCPConnectionActor`, whose `dispose()`
    hard-closes the connection and delivers `on_closed()` in the dispose
    turn.
    """
    None

  fun ref on_start_failure(reason: lori.StartFailureReason) =>
    """
    Called when a connection fails before starting.

    Fires when the TCP connection was accepted but never reached the
    HTTP-ready state — for example, when an SSL handshake fails. The
    `reason` identifies the cause (currently `lori.StartFailedSSL`).

    Neither `on_request()` nor `on_closed()` will fire for this
    connection. This is the only notification the actor receives.

    Override this to log or take action on connection failures. The
    default is a no-op.
    """
    None

  fun ref on_throttled() =>
    """
    Called when backpressure is applied on the connection.

    The TCP send buffer is full — stop generating response data until
    `on_unthrottled()` is called.
    """
    None

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    """
    Called for a chunk from `send_chunk()` whose bytes reached the OS.

    The `token` matches the `ChunkSendToken` returned by the
    `send_chunk()` call that produced the data. Fires asynchronously
    in a subsequent behavior turn — never during the `send_chunk()` call
    itself. Only user chunks produce this callback; internal sends
    (headers, terminal chunk, error responses) do not.

    No callback fires until the chunk's bytes reach the OS, and even then it
    can be lost: when the connection's close is reported first, any callback
    queued behind that report never reaches the actor. One way that happens
    is a delivery and the close landing in the same actor turn, where lori
    reports the close synchronously and the delivery is queued behind it
    (`ponylang/lori#345`).

    Use this for flow-controlled streaming: send a chunk, wait for the
    callback, then send the next chunk. Multiple chunks can be in flight
    simultaneously (windowed); use the tokens to track which have been
    delivered. Because a callback can go missing, an actor that sends the
    next chunk only after the previous one's callback can stop making
    progress.
    """
    None

  fun ref on_unthrottled() =>
    """
    Called when backpressure is released on the connection.

    The TCP send buffer has drained — response generation may resume.
    """
    None

  fun ref on_timer(token: lori.TimerToken) =>
    """
    Called when a one-shot timer created by `HTTPServer.set_timer()` fires.

    The `token` matches the one returned by `set_timer()`. A `set_timer()`
    call produces at most one callback. The timer is consumed before the
    callback, so it is safe to call `set_timer()` from within `on_timer()` to
    re-arm. No automatic re-arming occurs.

    A timer that comes due after the connection has started closing still
    fires. That is the point: a close the server starts is not complete until
    the peer closes its half, so `on_closed()` may be a long way off, and
    this callback is what your actor has to act on in the meantime. Calling
    `dispose()` on the actor from here closes without waiting on the peer.

    A new timer cannot be set once the connection is closing —
    `HTTPServer.set_timer()` returns `SetTimerNotOpen` — so this is the last
    callback of its kind for that connection.

    Unlike idle timeout, this timer has no I/O-reset behavior — send and
    receive activity do not change when it comes due.
    """
    None

  fun ref on_timer_failure() =>
    """
    Called when a user timer's ASIO event subscription fails (e.g., the
    kernel returned `ENOMEM` from `kevent` or `epoll_ctl`).

    Before this callback fires, the timer has been cancelled — the token
    returned by the originating `HTTPServer.set_timer()` call will not
    produce an `on_timer()` notification. If your actor stored that
    `TimerToken`, it is now stale; clear or replace it before re-arming.
    The application decides how to recover: call `set_timer()` again to
    retry, `HTTPServer.close()` to give up on the connection, or do
    nothing if the deadline no longer matters. The default is a no-op.
    """
    None
