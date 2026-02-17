use lori = "lori"
use "time"
use uri_pkg = "./uri"

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

actor _Connection is
  (lori.TCPConnectionActor & lori.ServerLifecycleEventReceiver
    & _RequestParserNotify & _ResponseQueueNotify)
  """
  Per-connection actor that owns TCP I/O, parsing, handler dispatch,
  response queue, and response sending.

  Implements the single-actor connection model: no actor boundaries
  between the TCP layer and application handler. Data arrives via
  `_on_received`, is fed to the parser, and parser callbacks are
  forwarded to the handler synchronously.

  Pipelined requests are supported: multiple requests can be in-flight
  on a single connection. The response queue ensures responses are sent
  in request order, regardless of the order handlers respond.

  Connections are persistent by default (HTTP/1.1 keep-alive). The
  connection closes when the client sends `Connection: close`, on
  HTTP/1.0 requests without `Connection: keep-alive`, after a parse
  error, or when the idle timeout expires.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Active
  let _handler: Handler
  var _queue: (_ResponseQueue | None) = None
  var _current_responder: (Responder | None) = None
  var _requests_pending: USize = 0
  var _parser: (_RequestParser | None) = None
  let _config: ServerConfig
  let _timers: (Timers | None)
  var _idle: Bool = true
  var _idle_timer: (Timer tag | None) = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    handler_factory: HandlerFactory,
    config: ServerConfig,
    timers: (Timers | None) = None)
  =>
    _config = config
    _timers = timers
    _handler = handler_factory()
    // All let fields now initialized + all var fields have defaults,
    // so `this` is ref — required by _ResponseQueue, TCPConnection.server,
    // and _RequestParser constructors.
    _queue = _ResponseQueue(this)
    _tcp_connection = lori.TCPConnection.server(auth, fd, this, this)
    _parser = _RequestParser(this, _config._parser_config())

  //
  // TCPConnectionActor / ServerLifecycleEventReceiver
  //

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    _start_idle_timer()

  fun ref _on_received(data: Array[U8] iso) =>
    _state.on_received(this, consume data)

  fun ref _on_closed() =>
    _cancel_idle_timer()
    _state.on_closed(this)

  fun ref _on_start_failure() =>
    // Connection failed before _on_started — handler was never activated.
    // Don't call _handler.closed(); just mark as closed for GC.
    _state = _Closed

  fun ref _on_throttled() =>
    _state.on_throttled(this)

  fun ref _on_unthrottled() =>
    _state.on_unthrottled(this)

  //
  // _RequestParserNotify — forwarding parser events to handler
  //

  fun ref request_received(
    method: Method,
    raw_uri: String val,
    version: Version,
    headers: Headers val)
  =>
    // Parse raw URI string into structured form. The parser already validated
    // basic syntax (no control characters); this catches structural failures
    // from the RFC 3986 parser (e.g., invalid authority in CONNECT targets).
    let parsed_uri: uri_pkg.URI val =
      if method is CONNECT then
        match uri_pkg.ParseURIAuthority(raw_uri)
        | let a: uri_pkg.URIAuthority val =>
          uri_pkg.URI(None, a, "", None, None)
        | let _: uri_pkg.URIParseError val =>
          parse_error(InvalidURI)
          return
        end
      else
        match uri_pkg.ParseURI(raw_uri)
        | let u: uri_pkg.URI val => u
        | let _: uri_pkg.URIParseError val =>
          parse_error(InvalidURI)
          return
        end
      end

    let keep_alive = _KeepAliveDecision(version, headers.get("connection"))
    match _queue
    | let q: _ResponseQueue =>
      let id = q.register(keep_alive)
      _current_responder = Responder._create(q, id, version)
    end
    _requests_pending = _requests_pending + 1
    _idle = false
    _cancel_idle_timer()

    // Safety net: close if too many pipelined requests are pending
    if _requests_pending > _config.max_pending_responses then
      _tcp_connection.send(_ErrorResponse.no_response())
      _close_connection()
      return
    end

    _handler.request(method, parsed_uri, version, headers)

  fun ref body_chunk(data: Array[U8] val) =>
    _handler.body_chunk(data)

  fun ref request_complete() =>
    match _current_responder
    | let r: Responder =>
      _current_responder = None
      _handler.request_complete(r)
    end

  fun ref parse_error(err: ParseError) =>
    // Send error directly to TCP (bypassing queue) then close.
    // Discarding pending pipelined responses is acceptable per HTTP spec
    // since parse errors indicate a corrupt data stream.
    _tcp_connection.send(_ErrorResponse.for_error(err))
    _close_connection()

  //
  // _ResponseQueueNotify — called by the response queue during
  // send_data/finish/unthrottle to delegate TCP I/O and lifecycle
  // decisions to this connection actor.
  //

  fun ref _flush_data(data: ByteSeq) =>
    """
    Send response data to the TCP connection.

    Called when data for the head-of-line entry is ready to send.
    On send error, closes the connection (which in turn closes the queue,
    making any remaining Responders inert).
    """
    match _tcp_connection.send(data)
    | let _: lori.SendError =>
      _close_connection()
    end

  fun ref _response_complete(keep_alive: Bool) =>
    """
    Called when a completed response has been fully flushed from the head
    of the queue.

    Decrements the pending request count and either closes the connection
    (if keep-alive is false) or starts the idle timer (if no more requests
    are pending).
    """
    _requests_pending = _requests_pending - 1
    if not keep_alive then
      _close_connection()
    elseif _requests_pending == 0 then
      _idle = true
      _start_idle_timer()
    end

  //
  // Idle timeout
  //

  // Sent by _IdleTimerNotify when the idle timer fires. Arrives
  // asynchronously — a new request may have started since the timer
  // was scheduled.
  be _idle_timeout() =>
    _state.on_idle_timeout(this)

  //
  // Internal methods called by state classes
  //

  fun ref _feed_parser(data: Array[U8] iso) =>
    """Feed incoming data to the request parser."""
    match _parser
    | let p: _RequestParser => p.parse(consume data)
    end

  fun ref _handle_closed() =>
    """Notify the handler that the connection has closed."""
    match _parser | let p: _RequestParser => p.stop() end
    match _queue | let q: _ResponseQueue => q.close() end
    _handler.closed()
    _state = _Closed

  fun ref _handle_throttled() =>
    """Apply backpressure: mute the TCP connection and notify the handler."""
    _tcp_connection.mute()
    match _queue | let q: _ResponseQueue => q.throttle() end
    _handler.throttled()

  fun ref _handle_unthrottled() =>
    """Release backpressure: unmute the TCP connection and notify the handler."""
    _tcp_connection.unmute()
    match _queue | let q: _ResponseQueue => q.unthrottle() end
    _handler.unthrottled()

  fun ref _handle_idle_timeout() =>
    """Close the connection if it is idle (between requests)."""
    if _idle then
      _close_connection()
    end

  fun ref _close_connection() =>
    """
    Close the connection and clean up all resources.

    Safe to call from within queue callbacks (e.g., `_response_complete`
    with `keep_alive=false`) — the `_Active` state guard prevents
    double-close. After this, any Responders the handler still holds
    become inert: their methods call through to the queue, which is
    closed and no-ops everything.
    """
    match _state
    | let _: _Active =>
      match _parser | let p: _RequestParser => p.stop() end
      match _queue | let q: _ResponseQueue => q.close() end
      _cancel_idle_timer()
      _handler.closed()
      _tcp_connection.close()
      _state = _Closed
    end

  //
  // Timer helpers
  //

  fun ref _start_idle_timer() =>
    if _config.idle_timeout == 0 then return end
    match _timers
    | let timers: Timers =>
      let timer = Timer(
        _IdleTimerNotify(this),
        _config.idle_timeout * 1_000_000_000)
      let t: Timer tag = timer
      timers(consume timer)
      _idle_timer = t
    end

  fun ref _cancel_idle_timer() =>
    match (_timers, _idle_timer)
    | (let timers: Timers, let timer: Timer tag) =>
      timers.cancel(timer)
      _idle_timer = None
    end

class _IdleTimerNotify is TimerNotify
  """Timer notify that sends an idle timeout message to a connection."""
  let _connection: _Connection tag

  new iso create(connection: _Connection tag) =>
    _connection = connection

  fun ref apply(timer: Timer, count: U64): Bool =>
    _connection._idle_timeout()
    false // One-shot: don't reschedule

  fun ref cancel(timer: Timer) =>
    None
