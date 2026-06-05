use lori = "lori"
use ssl_net = "ssl/net"
use uri_pkg = "uri"

class HTTPServer is
  (lori.ServerLifecycleEventReceiver & _RequestParserNotify
    & _ResponseQueueNotify)
  """
  HTTP protocol handler that manages parsing, response queuing, and
  connection lifecycle for a single HTTP connection.

  Stored as a field inside an `HTTPServerActor`. Handles all HTTP-level
  concerns — parsing incoming data, URI validation, response queue
  management, idle timeout scheduling, and backpressure — and delivers
  HTTP events to the actor via `HTTPServerLifecycleEventReceiver`
  callbacks.

  The protocol class implements lori's `ServerLifecycleEventReceiver`
  to receive TCP-level events from the connection, processes them through
  the HTTP parser, and forwards HTTP-level events to the owning actor.

  Use `none()` as the field default so that `this` is `ref` in the
  actor constructor body, then replace with `create()` or `ssl()`:

  ```pony
  actor MyServer is HTTPServerActor
    var _http: HTTPServer = HTTPServer.none()

    new create(auth: lori.TCPServerAuth, fd: U32,
      config: ServerConfig)
    =>
      _http = HTTPServer(auth, fd, this, config)
  ```
  """
  let _lifecycle_event_receiver: (HTTPServerLifecycleEventReceiver ref | None)
  let _config: (ServerConfig | None)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Active
  var _queue: (_ResponseQueue | None) = None
  var _current_request: (Request val | None) = None
  var _current_responder: (Responder | None) = None
  var _requests_pending: USize = 0
  var _requests_completed: USize = 0
  var _parser: (_RequestParser | None) = None
  var _idle: Bool = true
  embed _pending_sent_tokens: Array[(ChunkSendToken | None)]

  new none() =>
    """
    Create a placeholder protocol instance.

    Used as the default value for the `_http` field in `HTTPServerActor`
    implementations, allowing `this` to be `ref` in the actor constructor
    body. The placeholder is immediately replaced by `create()` or `ssl()`
    — its methods must never be called.
    """
    _lifecycle_event_receiver = None
    _config = None
    _pending_sent_tokens = Array[(ChunkSendToken | None)]

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    server_actor: HTTPServerActor ref,
    config: ServerConfig)
  =>
    """
    Create the protocol handler for a plain HTTP connection.

    Called inside the `HTTPServerActor` constructor. The `server_actor`
    parameter must be the actor's `this` — it provides the
    `HTTPServerLifecycleEventReceiver ref` for synchronous HTTP callbacks.
    """
    _lifecycle_event_receiver = server_actor
    _config = config
    _pending_sent_tokens = Array[(ChunkSendToken | None)]
    _queue = _ResponseQueue(this)
    _parser = _RequestParser(this, config._parser_config())
    _tcp_connection =
      lori.TCPConnection.server(auth, fd, server_actor, this)

  new ssl(
    auth: lori.TCPServerAuth,
    ssl_ctx: ssl_net.SSLContext val,
    fd: U32,
    server_actor: HTTPServerActor ref,
    config: ServerConfig)
  =>
    """
    Create the protocol handler for an HTTPS connection.

    Like `create`, but wraps the TCP connection in SSL using the provided
    `SSLContext`. Called inside the `HTTPServerActor` constructor for
    HTTPS connections.
    """
    _lifecycle_event_receiver = server_actor
    _config = config
    _pending_sent_tokens = Array[(ChunkSendToken | None)]
    _queue = _ResponseQueue(this)
    _parser = _RequestParser(this, config._parser_config())
    _tcp_connection =
      lori.TCPConnection.ssl_server(auth, ssl_ctx, fd, server_actor, this)

  fun ref _connection(): lori.TCPConnection =>
    """Return the underlying TCP connection."""
    _tcp_connection

  //
  // ServerLifecycleEventReceiver
  //

  fun ref _on_started() =>
    match _config
    | let c: ServerConfig =>
      _tcp_connection.idle_timeout(c.idle_timeout)
    end

  fun ref _on_received(data: Array[U8] iso) =>
    _state.on_received(this, consume data)

  fun ref _on_closed() =>
    _state.on_closed(this)

  fun ref _on_start_failure(reason: lori.StartFailureReason) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_start_failure(reason)
    | None => _Unreachable()
    end
    _state = _Closed

  fun ref _on_throttled() =>
    _state.on_throttled(this)

  fun ref _on_unthrottled() =>
    _state.on_unthrottled(this)

  fun ref _on_sent(token: lori.SendToken) =>
    _state.on_sent(this, token)

  fun ref _on_idle_timeout() =>
    _state.on_idle_timeout(this)

  fun ref _on_timer(token: lori.TimerToken) =>
    _state.on_timer(this, token)

  fun ref _on_idle_timer_failure() =>
    _state.on_idle_timer_failure(this)

  fun ref _on_timer_failure() =>
    _state.on_timer_failure(this)

  //
  // _RequestParserNotify — forwarding parser events to receiver
  //

  fun ref request_received(
    method: Method,
    raw_uri: String val,
    version: Version,
    headers: Headers val)
  =>
    // RFC 9110 §7.2 / RFC 9112 §3.2: an HTTP/1.1 request must carry exactly one
    // Host field — reject (400) a missing Host on HTTP/1.1. We additionally
    // reject a DUPLICATE Host on ANY version: a second Host line is request-
    // smuggling surface regardless of protocol version (security over strict
    // conformance). This needs the assembled headers, so it lives here, not in
    // the parser. Count Host field-LINES via values(), not get(): get() combines
    // repeated list-valued fields into one value, which would hide a duplicate
    // Host behind a single combined result.
    var host_count: USize = 0
    var host_value: (String val | None) = None
    for hdr in headers.values() do
      if hdr.name == "host" then
        host_count = host_count + 1
        // Capturing the last Host line's value is safe only because the
        // host_count > 1 check below rejects before host_value is ever used, so
        // a request that reaches the value gate has exactly one Host line.
        host_value = hdr.value
      end
    end
    if (host_count > 1) or ((host_count == 0) and (version is HTTP11)) then
      parse_error(BadHostHeader)
      return
    end

    // RFC 9110 §7.2 / RFC 9112 §3.2: when a Host is present, its value must be
    // a well-formed uri-host [ ":" port ]. The count check above only enforces
    // presence/uniqueness. Runs for every request-target form; syntax only — no
    // cross-check against an absolute-form/CONNECT authority.
    match host_value
    | let h: String val =>
      if not _HostValue.valid(h) then
        parse_error(InvalidHostValue)
        return
      end
    end

    // Parse raw URI string into structured form. The parser already validated
    // basic syntax (no control characters); this catches structural failures
    // from the RFC 3986 parser (e.g., invalid authority in CONNECT targets).
    let parsed_uri: uri_pkg.URI val =
      if method is CONNECT then
        match \exhaustive\ uri_pkg.ParseURIAuthority(raw_uri)
        | let a: uri_pkg.URIAuthority val =>
          uri_pkg.URI(None, a, "", None, None)
        | let _: uri_pkg.URIParseError val =>
          parse_error(InvalidURI)
          return
        end
      else
        match \exhaustive\ uri_pkg.ParseURI(raw_uri)
        | let u: uri_pkg.URI val => u
        | let _: uri_pkg.URIParseError val =>
          parse_error(InvalidURI)
          return
        end
      end

    let keep_alive = _KeepAliveDecision(version, headers.get("connection"))
    let cookies = ParseCookies.from_headers(headers)
    let req = Request(method, parsed_uri, version, headers, cookies)
    _current_request = req
    match _queue
    | let q: _ResponseQueue =>
      let id = q.register(keep_alive)
      _current_responder = Responder._create(q, id, version)
    else
      _Unreachable(); return
    end
    _requests_pending = _requests_pending + 1
    _idle = false

    // Safety net: close if too many pipelined requests are pending
    match \exhaustive\ _config
    | let c: ServerConfig =>
      if _requests_pending > c.max_pending_responses then
        _tcp_connection.send(_ErrorResponse.no_response())
        _close_connection()
        return
      end
    | None =>
      _Unreachable()
    end

    match (_lifecycle_event_receiver, _current_responder)
    | (let r: HTTPServerLifecycleEventReceiver ref, let resp: Responder) =>
      r.on_request(req, resp)
    else
      _Unreachable()
    end

  fun ref body_chunk(data: Array[U8] val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref =>
      r.on_body_chunk(data)
    | None =>
      _Unreachable()
    end

  fun ref request_complete() =>
    match (_lifecycle_event_receiver, _current_request, _current_responder)
    | (let recv: HTTPServerLifecycleEventReceiver ref,
      let req: Request val, let resp: Responder)
    =>
      _current_request = None
      _current_responder = None
      recv.on_request_complete(req, resp)
    else
      // request_complete only fires for a delivered request: the parser's
      // `_finish` returns early (checking `failed()`) when request_received
      // rejected, so this branch is unreachable.
      _Unreachable()
    end

  fun ref parse_error(err: ParseError) =>
    // Send error directly to TCP (bypassing queue) then close.
    // Discarding pending pipelined responses is acceptable per HTTP spec
    // since parse errors indicate a corrupt data stream. Stop the parser so it
    // delivers no further callbacks — parse_error may be called by the parser
    // itself or internally here (Host/URI rejection in request_received), and
    // in the latter case the parser is otherwise unaware the request was
    // rejected and would keep parsing.
    _tcp_connection.send(_ErrorResponse.for_error(err))
    match _parser
    | let p: _RequestParser => p.stop()
    end
    _close_connection()

  //
  // _ResponseQueueNotify — called by the response queue during
  // send_data/finish/unthrottle to delegate TCP I/O and lifecycle
  // decisions.
  //

  fun ref _flush_data(data: ByteSeq,
    token: (ChunkSendToken | None) = None)
  =>
    """
    Send response data to the TCP connection.

    Called when data for the head-of-line entry is ready to send.
    On successful send, pushes the HTTP-level token onto the FIFO so
    `_handle_sent` can correlate the lori `_on_sent` callback back to
    the originating `send_chunk()` call. On send error, closes the
    connection (which in turn closes the queue, making any remaining
    Responders inert).
    """
    match \exhaustive\ _tcp_connection.send(data)
    | let _: lori.SendToken =>
      _pending_sent_tokens.push(token)
    | let _: lori.SendError =>
      _close_connection()
    end

  fun ref _response_complete(keep_alive: Bool) =>
    """
    Called when a completed response has been fully flushed from the head
    of the queue.

    Decrements the pending request count, increments the completed count,
    and decides whether to close the connection. The check order is:
    keep-alive=false closes first (existing HTTP semantics), then
    max-requests check (connection resource limit), then idle if no more
    requests are pending. Pipelined requests already in flight still get
    served — the connection closes after the Nth response flushes.
    """
    _requests_pending = _requests_pending - 1
    _requests_completed = _requests_completed + 1
    if not keep_alive then
      _close_connection()
    elseif _max_requests_reached() then
      _close_connection()
    elseif _requests_pending == 0 then
      _idle = true
    end

  fun _max_requests_reached(): Bool =>
    """Check whether the connection has reached its max-requests limit."""
    match _config
    | let c: ServerConfig =>
      match c.max_requests_per_connection
      | let max: MaxRequestsPerConnection => _requests_completed >= max()
      else false
      end
    else false
    end

  //
  // Internal methods called by state classes and HTTPServerActor
  //

  fun ref _feed_parser(data: Array[U8] iso) =>
    """Feed incoming data to the request parser."""
    match _parser
    | let p: _RequestParser => p.parse(consume data)
    end

  fun ref _handle_closed() =>
    """Notify the receiver that the connection has closed."""
    match _parser | let p: _RequestParser => p.stop() end
    match _queue | let q: _ResponseQueue => q.close() end
    _pending_sent_tokens.clear()
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_closed()
    | None => _Unreachable()
    end
    _state = _Closed

  fun ref _handle_throttled() =>
    """Apply backpressure: mute the TCP connection and notify the receiver."""
    _tcp_connection.mute()
    match _queue | let q: _ResponseQueue => q.throttle() end
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_throttled()
    | None => _Unreachable()
    end

  fun ref _handle_unthrottled() =>
    """Release backpressure: unmute the TCP connection and notify the receiver."""
    _tcp_connection.unmute()
    match _queue | let q: _ResponseQueue => q.unthrottle() end
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_unthrottled()
    | None => _Unreachable()
    end

  fun ref _handle_sent(token: lori.SendToken) =>
    """
    Correlate a lori send completion back to an HTTP-level chunk token.

    Pops the next entry from the FIFO. If it's a `ChunkSendToken`,
    delivers `on_chunk_sent(token)` to the actor. If `None`, it was an
    internal send (headers, terminal chunk, complete response) — skip it.
    """
    try
      match _pending_sent_tokens.shift()?
      | let ct: ChunkSendToken =>
        match \exhaustive\ _lifecycle_event_receiver
        | let r: HTTPServerLifecycleEventReceiver ref => r.on_chunk_sent(ct)
        | None => _Unreachable()
        end
      end
    else
      _Unreachable()
    end

  fun ref _handle_idle_timeout() =>
    """Close the connection if it is idle (between requests)."""
    if _idle then
      _close_connection()
    end

  fun ref _handle_timer(token: lori.TimerToken) =>
    """Forward one-shot timer firing to the receiver."""
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_timer(token)
    | None => _Unreachable()
    end

  fun ref _handle_idle_timer_failure() =>
    """
    Auto-rearm the idle timer using the originally configured duration.
    Stallion owns the idle timer, so recovery happens silently here
    rather than leaving the connection without idle protection or
    surfacing a failure users can't meaningfully act on.
    """
    match \exhaustive\ _config
    | let c: ServerConfig => _tcp_connection.idle_timeout(c.idle_timeout)
    | None => _Unreachable()
    end

  fun ref _handle_timer_failure() =>
    """Forward user timer ASIO subscription failure to the receiver."""
    match \exhaustive\ _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref =>
      r.on_timer_failure()
    | None => _Unreachable()
    end

  fun ref close() =>
    """
    Close the connection from the server actor.

    Use this when the actor needs to force-close the connection — for
    example, after rejecting a request early (413 Payload Too Large) via
    the `Responder` delivered in `on_request()`. Safe to call at any time;
    idempotent due to the `_Active` state guard.
    """
    _close_connection()

  fun ref yield_read() =>
    """
    Request the read loop to exit after the current callback returns,
    giving other actors a chance to run. Reading resumes automatically
    in the next scheduler turn — no explicit action is needed.

    Call this from HTTP callbacks (`on_request`, `on_body_chunk`,
    `on_request_complete`) to implement yield policies such as yielding
    every N requests during pipelining storms or every N bytes of body
    data.

    Operates at the TCP level: it prevents the *next* socket read, not
    the processing of already-buffered data. If a single receive delivers
    a buffer containing multiple pipelined requests, all are parsed and
    all callbacks fire before the yield takes effect.
    """
    _tcp_connection.yield_read()

  fun ref set_timer(duration: lori.TimerDuration)
    : (lori.TimerToken | lori.SetTimerError)
  =>
    """
    Create a one-shot timer that fires `on_timer()` after the configured
    duration. Returns a `TimerToken` on success, or a `SetTimerError` on
    failure.

    Unlike idle timeout, this timer has no I/O-reset behavior — it fires
    unconditionally after the duration elapses, regardless of send/receive
    activity. There is no automatic re-arming; call `set_timer()` again from
    `on_timer()` for repetition.

    Only one timer can be active at a time. Setting a timer while one is
    already active returns `SetTimerAlreadyActive` — call `cancel_timer()`
    first. Requires the connection to be open; returns `SetTimerNotOpen` if
    not.

    A successfully returned `TimerToken` may still fail asynchronously if
    the underlying ASIO subscription is lost — see `on_timer_failure()`.

    Use `lori.MakeTimerDuration(milliseconds)` to create the duration value.
    """
    _tcp_connection.set_timer(duration)

  fun ref cancel_timer(token: lori.TimerToken) =>
    """
    Cancel an active timer. No-op if the token doesn't match the active timer
    (already fired, already cancelled, wrong token). Safe to call with stale
    tokens.
    """
    _tcp_connection.cancel_timer(token)

  fun ref _close_connection() =>
    """
    Close the connection and clean up all resources.

    Safe to call from within queue callbacks (e.g., `_response_complete`
    with `keep_alive=false`) — the `_Active` state guard prevents
    double-close. After this, any Responders the actor still holds
    become inert: their methods call through to the queue, which is
    closed and no-ops everything.
    """
    match _state
    | let _: _Active =>
      match _parser | let p: _RequestParser => p.stop() end
      match _queue | let q: _ResponseQueue => q.close() end
      _pending_sent_tokens.clear()
      match \exhaustive\ _lifecycle_event_receiver
      | let r: HTTPServerLifecycleEventReceiver ref => r.on_closed()
      | None => _Unreachable()
      end
      _tcp_connection.close()
      _state = _Closed
    end
