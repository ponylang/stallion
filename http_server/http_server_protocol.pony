use lori = "lori"
use ssl_net = "ssl/net"
use "time"
use uri_pkg = "uri"

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
  actor constructor body, then replace with `create()`:

  ```pony
  actor MyServer is HTTPServerActor
    var _http: HTTPServer = HTTPServer.none()

    new create(auth: lori.TCPServerAuth, fd: U32,
      config: ServerConfig,
      ssl_ctx: (ssl_net.SSLContext val | None),
      timers: (Timers | None))
    =>
      _http = HTTPServer(auth, fd, ssl_ctx, this, config,
        timers)
  ```
  """
  let _lifecycle_event_receiver: (HTTPServerLifecycleEventReceiver ref | None)
  let _enclosing: (HTTPServerActor | None)
  let _config: (ServerConfig | None)
  let _timers: (Timers | None)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Active
  var _queue: (_ResponseQueue | None) = None
  var _current_responder: (Responder | None) = None
  var _requests_pending: USize = 0
  var _parser: (_RequestParser | None) = None
  var _idle: Bool = true
  var _idle_timer: (Timer tag | None) = None

  new none() =>
    """
    Create a placeholder protocol instance.

    Used as the default value for the `_http` field in `HTTPServerActor`
    implementations, allowing `this` to be `ref` in the actor constructor
    body. The placeholder is immediately replaced by `create()` — its
    methods must never be called.
    """
    _lifecycle_event_receiver = None
    _enclosing = None
    _config = None
    _timers = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    ssl_ctx: (ssl_net.SSLContext val | None),
    server_actor: HTTPServerActor ref,
    config: ServerConfig,
    timers: (Timers | None))
  =>
    """
    Create the protocol handler for a new connection.

    Called inside the `HTTPServerActor` constructor. The `server_actor`
    parameter must be the actor's `this` — it provides both the
    `HTTPServerLifecycleEventReceiver ref` for synchronous HTTP callbacks and
    the `HTTPServerActor` for idle timer notifications.
    """
    _lifecycle_event_receiver = server_actor
    _enclosing = server_actor
    _config = config
    _timers = timers
    // All let fields now initialized + all var fields have defaults,
    // so `this` is ref — required by _ResponseQueue, TCPConnection.server,
    // and _RequestParser constructors.
    _queue = _ResponseQueue(this)
    _parser = _RequestParser(this, config._parser_config())
    _tcp_connection = match ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      lori.TCPConnection.ssl_server(auth, ctx, fd, server_actor, this)
    else
      lori.TCPConnection.server(auth, fd, server_actor, this)
    end

  fun ref _connection(): lori.TCPConnection =>
    """Return the underlying TCP connection."""
    _tcp_connection

  //
  // ServerLifecycleEventReceiver
  //

  fun ref _on_started() =>
    _start_idle_timer()

  fun ref _on_received(data: Array[U8] iso) =>
    _state.on_received(this, consume data)

  fun ref _on_closed() =>
    _cancel_idle_timer()
    _state.on_closed(this)

  fun ref _on_start_failure() =>
    // Connection failed before _on_started — receiver was never activated.
    // Don't call _receiver.closed(); just mark as closed for GC.
    _state = _Closed

  fun ref _on_throttled() =>
    _state.on_throttled(this)

  fun ref _on_unthrottled() =>
    _state.on_unthrottled(this)

  //
  // _RequestParserNotify — forwarding parser events to receiver
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
    match _config
    | let c: ServerConfig =>
      if _requests_pending > c.max_pending_responses then
        _tcp_connection.send(_ErrorResponse.no_response())
        _close_connection()
        return
      end
    | None =>
      _Unreachable()
    end

    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref =>
      r.request(Request(method, parsed_uri, version, headers))
    | None =>
      _Unreachable()
    end

  fun ref body_chunk(data: Array[U8] val) =>
    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref =>
      r.body_chunk(data)
    | None =>
      _Unreachable()
    end

  fun ref request_complete() =>
    match _current_responder
    | let r: Responder =>
      _current_responder = None
      match _lifecycle_event_receiver
      | let recv: HTTPServerLifecycleEventReceiver ref =>
        recv.request_complete(r)
      | None =>
        _Unreachable()
      end
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
  // decisions.
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
    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.closed()
    | None => _Unreachable()
    end
    _state = _Closed

  fun ref _handle_throttled() =>
    """Apply backpressure: mute the TCP connection and notify the receiver."""
    _tcp_connection.mute()
    match _queue | let q: _ResponseQueue => q.throttle() end
    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.throttled()
    | None => _Unreachable()
    end

  fun ref _handle_unthrottled() =>
    """Release backpressure: unmute the TCP connection and notify the receiver."""
    _tcp_connection.unmute()
    match _queue | let q: _ResponseQueue => q.unthrottle() end
    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.unthrottled()
    | None => _Unreachable()
    end

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
    double-close. After this, any Responders the actor still holds
    become inert: their methods call through to the queue, which is
    closed and no-ops everything.
    """
    match _state
    | let _: _Active =>
      match _parser | let p: _RequestParser => p.stop() end
      match _queue | let q: _ResponseQueue => q.close() end
      _cancel_idle_timer()
      match _lifecycle_event_receiver
      | let r: HTTPServerLifecycleEventReceiver ref => r.closed()
      | None => _Unreachable()
      end
      _tcp_connection.close()
      _state = _Closed
    end

  //
  // Timer helpers
  //

  fun ref _start_idle_timer() =>
    match _config
    | let c: ServerConfig =>
      if c.idle_timeout == 0 then return end
      match (_timers, _enclosing)
      | (let timers: Timers, let a: HTTPServerActor) =>
        let timer = Timer(
          _IdleTimerNotify(a),
          c.idle_timeout * 1_000_000_000)
        let t: Timer tag = timer
        timers(consume timer)
        _idle_timer = t
      end
    end

  fun ref _cancel_idle_timer() =>
    match (_timers, _idle_timer)
    | (let timers: Timers, let timer: Timer tag) =>
      timers.cancel(timer)
      _idle_timer = None
    end

class _IdleTimerNotify is TimerNotify
  """Timer notify that sends an idle timeout message to the server actor."""
  let _server_actor: HTTPServerActor

  new iso create(server_actor: HTTPServerActor) =>
    _server_actor = server_actor

  fun ref apply(timer: Timer, count: U64): Bool =>
    _server_actor._idle_timeout()
    false // One-shot: don't reschedule

  fun ref cancel(timer: Timer) =>
    None
