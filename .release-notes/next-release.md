## Add cooperative scheduler yielding for HTTP connections

Under sustained pipelined traffic, a single connection's read loop can monopolize the Pony scheduler. `HTTPServer.yield_read()` lets the application exit the read loop cooperatively, giving other actors a chance to run. Reading resumes automatically in the next scheduler turn.

Call `yield_read()` from HTTP callbacks to implement any yield policy — request count, byte threshold, time-based, etc.:

```pony
fun ref on_request_complete(request': Request val,
  responder: Responder)
=>
  _request_count = _request_count + 1
  // ... send response ...

  // Yield every 5 requests to let other actors run
  if (_request_count % 5) == 0 then
    _http.yield_read()
  end
```

Unlike `mute()`/`unmute()` on the underlying TCP connection, `yield_read()` is a one-shot pause — the read loop resumes on its own without explicit action. The yield operates at the TCP level: if a single receive delivers multiple pipelined requests, all are parsed and all callbacks fire before the yield takes effect.

