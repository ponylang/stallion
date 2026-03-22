## Add one-shot timer API

Surfaces lori's general-purpose one-shot timer through the HTTP server layer. Use it for request processing deadlines or any application-level timeout where I/O activity should not postpone the timeout.

`HTTPServer.set_timer(duration)` creates a timer that fires the `on_timer(token)` callback after the configured duration. Unlike idle timeout, this timer fires unconditionally regardless of send/receive activity. Only one timer can be active per connection at a time.

The typical pattern is a processing deadline: set a timer, delegate work to another actor, and race the result against the deadline. If the work completes first, cancel the timer and send the response. If the timer fires first, send a timeout:

```pony
actor MyServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _database: Database tag

  // These two fields together represent "a deadline is in flight."
  // When both are non-None, we're waiting for either the worker or the
  // timer to complete. Whichever path fires first sets both back to None,
  // which prevents the other path's match from succeeding — that's how
  // we ensure exactly one response per request.
  var _timer: (lori.TimerToken | None) = None
  var _responder: (stallion.Responder | None) = None

  // ... constructor ...

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
        // query_result and on_timer can check whether a deadline is
        // in flight and respond if they're the first to arrive.
        _timer = t
        _responder = responder
        _database.query(request', this)
      | let err: lori.SetTimerError => None
      end
    end

  be query_result(data: String val) =>
    // The worker finished. Check whether a deadline is still in flight
    // by matching on both fields — if either is None, the timer already
    // fired and responded, so there's nothing to do.
    match (_timer, _responder)
    | (let t: lori.TimerToken, let r: stallion.Responder) =>
      // We won the race. Cancel the timer so on_timer doesn't fire,
      // then clear both fields to disarm the deadline. Even if
      // cancel_timer didn't exist, clearing the fields would be enough
      // — on_timer's match would fail. But cancelling avoids a
      // needless callback from lori.
      _http.cancel_timer(t)
      _timer = None
      _responder = None
      let response = stallion.ResponseBuilder(stallion.StatusOK)
        .add_header("Content-Length", data.size().string())
        .finish_headers()
        .add_chunk(data)
        .build()
      r.respond(response)
    end

  fun ref on_timer(token: lori.TimerToken) =>
    // The deadline expired. Check whether a deadline is still in flight.
    // The `if t == token` guard adds an extra check: it ensures we're
    // acting on the current timer, not a stale token left over from a
    // previous request whose query_result already cleared and re-armed.
    match (_timer, _responder)
    | (let t: lori.TimerToken, let r: stallion.Responder) if t == token =>
      // We won the race. Clear both fields to disarm the deadline so
      // that if query_result arrives later, its match fails silently.
      _timer = None
      _responder = None
      let body: String val = "Request timed out"
      let response = stallion.ResponseBuilder(stallion.StatusRequestTimeout)
        .add_header("Content-Length", body.size().string())
        .finish_headers()
        .add_chunk(body)
        .build()
      r.respond(response)
    end
```

New API:

- `HTTPServer.set_timer(duration: lori.TimerDuration): (lori.TimerToken | lori.SetTimerError)` -- create a one-shot timer
- `HTTPServer.cancel_timer(token: lori.TimerToken)` -- cancel an active timer
- `HTTPServerLifecycleEventReceiver.on_timer(token: lori.TimerToken)` -- callback when the timer fires
