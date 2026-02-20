"""
HTTP server for Pony, built on lori.

A listener actor implements `lori.TCPListenerActor` and creates
`HTTPServerActor` instances in `_on_accept`. Each connection actor owns
an `HTTPServer` that handles HTTP parsing and response management,
delivering HTTP events via `HTTPServerLifecycleEventReceiver` callbacks.

```pony
use "http_server"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    MyListener(auth, "localhost", "8080")

actor MyListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ServerConfig

  new create(auth: lori.TCPListenAuth, host: String, port: String) =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config, None)

actor MyServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: ServerConfig,
    timers: (Timers | None))
  =>
    _http = HTTPServer(auth, fd, this, config, timers)

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val,
    responder: Responder)
  =>
    let body: String val = "Hello!"
    let response = ResponseBuilder(StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
```

For streaming responses, use chunked transfer encoding. Each
`send_chunk()` returns a `ChunkSendToken` — override `on_chunk_sent()`
to drive flow-controlled delivery:

```pony
fun ref on_request_complete(request': Request val,
  responder: Responder)
=>
  responder.start_chunked_response(StatusOK)
  let token = responder.send_chunk("chunk 1")
  // When on_chunk_sent(token) fires, send the next chunk...
  responder.send_chunk("chunk 2")
  responder.finish_response()
```

For HTTPS, use `HTTPServer.ssl` instead of `HTTPServer`. Store an
`SSLContext val` in the listener and pass it through in `_on_accept`:

```pony
use "http_server"
use "files"
use "ssl/net"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let sslctx = recover val
      SSLContext
        .> set_cert(
          FilePath(FileAuth(env.root), "cert.pem"),
          FilePath(FileAuth(env.root), "key.pem"))?
        .> set_client_verify(false)
        .> set_server_verify(false)
    end
    let auth = lori.TCPListenAuth(env.root)
    MyListener(auth, "localhost", "8443", sslctx)

actor MyListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ServerConfig
  let _ssl_ctx: SSLContext val

  new create(auth: lori.TCPListenAuth, host: String, port: String,
    ssl_ctx: SSLContext val)
  =>
    _ssl_ctx = ssl_ctx
    _server_auth = lori.TCPServerAuth(auth)
    _config = ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config, _ssl_ctx, None)
```

The actor explicitly chooses `HTTPServer` (plain HTTP) or `HTTPServer.ssl`
(HTTPS) in its constructor. The `MyServer` actor in the HTTPS example
would use `HTTPServer.ssl(auth, ssl_ctx, fd, this, config, timers)`
instead of `HTTPServer(auth, fd, this, config, timers)`.
"""

use lori = "lori"
use ssl_net = "ssl/net"
use "time"
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
      config: ServerConfig,
      timers: (Timers | None))
    =>
      _http = HTTPServer(auth, fd, this, config, timers)
  ```
  """
  let _lifecycle_event_receiver: (HTTPServerLifecycleEventReceiver ref | None)
  let _enclosing: (HTTPServerActor | None)
  let _config: (ServerConfig | None)
  let _timers: (Timers | None)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Active
  var _queue: (_ResponseQueue | None) = None
  var _current_request: (Request val | None) = None
  var _current_responder: (Responder | None) = None
  var _requests_pending: USize = 0
  var _parser: (_RequestParser | None) = None
  var _idle: Bool = true
  var _idle_timer: (Timer tag | None) = None
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
    _enclosing = None
    _config = None
    _timers = None
    _pending_sent_tokens = Array[(ChunkSendToken | None)]

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    server_actor: HTTPServerActor ref,
    config: ServerConfig,
    timers: (Timers | None))
  =>
    """
    Create the protocol handler for a plain HTTP connection.

    Called inside the `HTTPServerActor` constructor. The `server_actor`
    parameter must be the actor's `this` — it provides both the
    `HTTPServerLifecycleEventReceiver ref` for synchronous HTTP callbacks and
    the `HTTPServerActor` for idle timer notifications.
    """
    _lifecycle_event_receiver = server_actor
    _enclosing = server_actor
    _config = config
    _timers = timers
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
    config: ServerConfig,
    timers: (Timers | None))
  =>
    """
    Create the protocol handler for an HTTPS connection.

    Like `create`, but wraps the TCP connection in SSL using the provided
    `SSLContext`. Called inside the `HTTPServerActor` constructor for
    HTTPS connections.
    """
    _lifecycle_event_receiver = server_actor
    _enclosing = server_actor
    _config = config
    _timers = timers
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
    _start_idle_timer()

  fun ref _on_received(data: Array[U8] iso) =>
    _state.on_received(this, consume data)

  fun ref _on_closed() =>
    _cancel_idle_timer()
    _state.on_closed(this)

  fun ref _on_start_failure() =>
    // Connection failed before _on_started — receiver was never activated.
    // Don't call _receiver.on_closed(); just mark as closed for GC.
    _state = _Closed

  fun ref _on_throttled() =>
    _state.on_throttled(this)

  fun ref _on_unthrottled() =>
    _state.on_unthrottled(this)

  fun ref _on_sent(token: lori.SendToken) =>
    _state.on_sent(this, token)

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
    let req = Request(method, parsed_uri, version, headers)
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

    match (_lifecycle_event_receiver, _current_responder)
    | (let r: HTTPServerLifecycleEventReceiver ref, let resp: Responder) =>
      r.on_request(req, resp)
    else
      _Unreachable()
    end

  fun ref body_chunk(data: Array[U8] val) =>
    match _lifecycle_event_receiver
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
      _Unreachable()
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
    match _tcp_connection.send(data)
    | let _: lori.SendToken =>
      _pending_sent_tokens.push(token)
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
    _pending_sent_tokens.clear()
    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_closed()
    | None => _Unreachable()
    end
    _state = _Closed

  fun ref _handle_throttled() =>
    """Apply backpressure: mute the TCP connection and notify the receiver."""
    _tcp_connection.mute()
    match _queue | let q: _ResponseQueue => q.throttle() end
    match _lifecycle_event_receiver
    | let r: HTTPServerLifecycleEventReceiver ref => r.on_throttled()
    | None => _Unreachable()
    end

  fun ref _handle_unthrottled() =>
    """Release backpressure: unmute the TCP connection and notify the receiver."""
    _tcp_connection.unmute()
    match _queue | let q: _ResponseQueue => q.unthrottle() end
    match _lifecycle_event_receiver
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
        match _lifecycle_event_receiver
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

  fun ref close() =>
    """
    Close the connection from the server actor.

    Use this when the actor needs to force-close the connection — for
    example, after rejecting a request early (413 Payload Too Large) via
    the `Responder` delivered in `on_request()`. Safe to call at any time;
    idempotent due to the `_Active` state guard.
    """
    _close_connection()

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
      _cancel_idle_timer()
      match _lifecycle_event_receiver
      | let r: HTTPServerLifecycleEventReceiver ref => r.on_closed()
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
