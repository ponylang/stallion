"""
Request processing deadline using one-shot timers. Sets a 5-second deadline
on each request, then delegates to a worker actor. If the worker responds
before the deadline, the timer is cancelled and the result is sent. If the
deadline fires first, the server responds with 408 Request Timeout.

Demonstrates `HTTPServer.set_timer()`, `HTTPServer.cancel_timer()`, and
`on_timer()` in a deadline pattern where the timer closes the request if
the worker has not responded.

Try it:
  curl http://localhost:8080/
"""
