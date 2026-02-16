use lori = "lori"
use "time"

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
    & _RequestParserNotify)
  """
  Per-connection actor that owns TCP I/O, parsing, handler dispatch,
  and response sending.

  Implements the single-actor connection model: no actor boundaries
  between the TCP layer and application handler. Data arrives via
  `_on_received`, is fed to the parser, and parser callbacks are
  forwarded to the handler synchronously.

  Connections are persistent by default (HTTP/1.1 keep-alive). The
  connection closes when the client sends `Connection: close`, on
  HTTP/1.0 requests without `Connection: keep-alive`, after a parse
  error, or when the idle timeout expires.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Active
  let _responder: Responder
  let _handler: Handler
  var _parser: (_RequestParser | None) = None
  let _config: ServerConfig
  let _timers: (Timers | None)
  var _keep_alive: Bool = true
  var _idle: Bool = true
  var _idle_timer: (Timer tag | None) = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    handler_factory: HandlerFactory,
    config: ServerConfig,
    timers: (Timers | None) = None)
  =>
    // Initialize responder and handler first with placeholder connection.
    // _parser defaults to None, so all fields are now initialized and
    // `this` becomes `ref` — required by TCPConnection.server and
    // _RequestParser.
    _config = config
    _timers = timers
    _responder = Responder._create(_tcp_connection)
    _handler = handler_factory(_responder)
    _tcp_connection = lori.TCPConnection.server(auth, fd, this, this)
    _responder._set_connection(_tcp_connection)
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
    uri: String val,
    version: Version,
    headers: Headers val)
  =>
    _keep_alive = _KeepAliveDecision(version, headers.get("connection"))
    _idle = false
    _cancel_idle_timer()
    _responder._set_version(version)
    _handler.request(method, uri, version, headers)

  fun ref body_chunk(data: Array[U8] val) =>
    _handler.body_chunk(data)

  fun ref request_complete() =>
    _handler.request_complete()

    // If handler didn't respond, send 500 and close unconditionally.
    // Protocol state is uncertain so we always close regardless of
    // _keep_alive.
    if not _responder.responded() then
      _tcp_connection.send(_ErrorResponse.no_response())
      _tcp_connection.close()
      _state = _Closed
      return
    end

    if _keep_alive then
      _responder._reset()
      _idle = true
      _start_idle_timer()
    else
      _tcp_connection.close()
      _state = _Closed
    end

  fun ref parse_error(err: ParseError) =>
    _tcp_connection.send(_ErrorResponse.for_error(err))
    _tcp_connection.close()
    _state = _Closed

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
    _handler.closed()
    _state = _Closed

  fun ref _handle_throttled() =>
    """Apply backpressure: mute the TCP connection and notify the handler."""
    _tcp_connection.mute()
    _handler.throttled()

  fun ref _handle_unthrottled() =>
    """Release backpressure: unmute the TCP connection and notify the handler."""
    _tcp_connection.unmute()
    _handler.unthrottled()

  fun ref _handle_idle_timeout() =>
    """Close the connection if it is idle (between requests)."""
    if _idle then
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
