"""
Request processing deadline using one-shot timers. Sets a 5-second deadline
on each request, then delegates to a worker actor. If the worker responds
before the deadline, the timer is cancelled and the result is sent. If the
deadline fires first, the server responds with 408 Request Timeout.

Demonstrates `HTTPServer.set_timer()`, `HTTPServer.cancel_timer()`, and
`on_timer()` in a deadline pattern where the timer is a safety net for
slow or unresponsive async work.

Try it:
  curl http://localhost:8080/
"""
use stallion = "../../stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let worker = Worker
    Listener(auth, "0.0.0.0", "8080", env.out, worker)

actor Listener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _out: OutStream
  let _config: stallion.ServerConfig
  let _server_auth: lori.TCPServerAuth
  let _worker: Worker tag

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    out: OutStream,
    worker: Worker tag)
  =>
    _out = out
    _worker = worker
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    DeadlineServer(_server_auth, fd, _config, _worker)

  fun ref _on_listening() =>
    try
      (let host, let port) = _tcp_listener.local_address().name()?
      _out.print("Server listening on " + host + ":" + port)
    else
      _out.print("Server listening")
    end

  fun ref _on_listen_failure() =>
    _out.print("Failed to start server")

  fun ref _on_closed() =>
    _out.print("Server closed")

actor Worker
  """
  Simulates async work. In a real application this could be a database
  query, an external API call, or any computation that might hang or
  run slow.
  """

  be process(server: DeadlineServer tag, path: String val) =>
    // Responds immediately — in production this might take seconds or
    // hang entirely, which is what the deadline timer guards against.
    server.work_complete("Hello! Processed: " + path)

actor DeadlineServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _worker: Worker tag

  // These two fields together represent "a deadline is in flight."
  // When both are non-None, we're waiting for either the worker or the
  // timer to complete. Whichever path fires first sets both back to None,
  // which prevents the other path's match from succeeding — that's how
  // we ensure exactly one response per request.
  var _responder: (stallion.Responder | None) = None
  var _timer_token: (lori.TimerToken | None) = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig,
    worker: Worker tag)
  =>
    _worker = worker
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    // Create a 5-second deadline. MakeTimerDuration validates the
    // millisecond value and returns a TimerDuration on success.
    match lori.MakeTimerDuration(5_000)
    | let d: lori.TimerDuration =>
      // set_timer returns a TimerToken on success, or a SetTimerError
      // if the connection isn't open or a timer is already active.
      match _http.set_timer(d)
      | let t: lori.TimerToken =>
        // Arm the deadline: store the token and responder so both
        // work_complete and on_timer can check whether a deadline is
        // in flight and respond if they're the first to arrive.
        _responder = responder
        _timer_token = t
        _worker.process(this, request'.uri.path)
      | lori.SetTimerAlreadyActive =>
        // Only one timer per connection. A previous request's timer
        // is still active — respond immediately instead of queuing.
        _respond(responder, stallion.StatusOK,
          "Timer busy — immediate response")
      | lori.SetTimerNotOpen =>
        None
      end
    end

  be work_complete(result: String val) =>
    // The worker finished. Check whether a deadline is still in flight
    // by matching on both fields — if either is None, the timer already
    // fired and responded, so there's nothing to do.
    match (_timer_token, _responder)
    | (let t: lori.TimerToken, let r: stallion.Responder) =>
      // We won the race. Cancel the timer so on_timer doesn't fire,
      // then clear both fields to disarm the deadline. Even if
      // cancel_timer didn't exist, clearing the fields would be enough
      // — on_timer's match would fail. But cancelling avoids a
      // needless callback from lori.
      _http.cancel_timer(t)
      _timer_token = None
      _responder = None
      _respond(r, stallion.StatusOK, result)
    end

  fun ref on_timer(token: lori.TimerToken) =>
    // The deadline expired. Check whether a deadline is still in flight.
    // The `if t == token` guard adds an extra check: it ensures we're
    // acting on the current timer, not a stale token left over from a
    // previous request whose work_complete already cleared and re-armed.
    match (_timer_token, _responder)
    | (let t: lori.TimerToken, let r: stallion.Responder) if t == token =>
      // We won the race. Clear both fields to disarm the deadline so
      // that if work_complete arrives later, its match fails silently.
      _timer_token = None
      _responder = None
      _respond(r, stallion.StatusRequestTimeout, "Request timed out")
    end

  fun _respond(responder: stallion.Responder ref, status: stallion.Status,
    body: String val)
  =>
    let response = stallion.ResponseBuilder(status)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
