use "net"

trait ref _ConnectionState
  """
  Connection lifecycle state.

  Routes net's events to the server methods that are valid in the current
  state: `_Active` (processing requests, including idle keep-alive periods),
  `_Closing` (stallion has stopped taking new work, and net can still report
  send outcomes for data already handed to it), and `_Closed` (every
  operation is a no-op).
  """

  fun ref on_received(server: HTTPServer ref, data: Array[U8] iso)
    """
    Handle incoming data from the TCP connection.
    """

  fun ref on_closed(server: HTTPServer ref)
    """
    Handle connection close notification.
    """

  fun ref on_throttled(server: HTTPServer ref)
    """
    Handle backpressure applied notification.
    """

  fun ref on_unthrottled(server: HTTPServer ref)
    """
    Handle backpressure released notification.
    """

  fun ref on_sent(server: HTTPServer ref, token: SendToken)
    """
    Handle send completion notification from net.
    """

  fun ref on_send_failed(server: HTTPServer ref, token: SendToken)
    """
    Handle send failure notification from net.
    """

  fun ref on_idle_timeout(server: HTTPServer ref)
    """
    Handle connection going idle.
    """

  fun ref on_timer(server: HTTPServer ref, token: TimerToken)
    """
    Handle one-shot timer firing.
    """

  fun ref on_idle_timer_failure(server: HTTPServer ref)
    """
    Handle idle timer ASIO subscription failure.
    """

  fun ref on_timer_failure(server: HTTPServer ref)
    """
    Handle user timer ASIO subscription failure.
    """

  fun ref close(server: HTTPServer ref)
    """
    Handle a request to close the connection.
    """

class ref _Active is _ConnectionState
  """
  Connection is active — parsing requests and dispatching to the receiver.
  """

  fun ref on_received(server: HTTPServer ref, data: Array[U8] iso) =>
    server._feed_parser(consume data)

  fun ref on_closed(server: HTTPServer ref) =>
    server._handle_closed()

  fun ref on_throttled(server: HTTPServer ref) =>
    server._handle_throttled()

  fun ref on_unthrottled(server: HTTPServer ref) =>
    server._handle_unthrottled()

  fun ref on_sent(server: HTTPServer ref, token: SendToken) =>
    server._handle_sent(token)

  fun ref on_send_failed(server: HTTPServer ref, token: SendToken) =>
    server._handle_send_failed(token)

  fun ref on_idle_timeout(server: HTTPServer ref) =>
    server._handle_idle_timeout()

  fun ref on_timer(server: HTTPServer ref, token: TimerToken) =>
    server._handle_timer(token)

  fun ref on_idle_timer_failure(server: HTTPServer ref) =>
    server._handle_idle_timer_failure()

  fun ref on_timer_failure(server: HTTPServer ref) =>
    server._handle_timer_failure()

  fun ref close(server: HTTPServer ref) =>
    server._start_close()

class ref _Closing is _ConnectionState
  """
  Connection is closing — stallion has stopped taking new work, and net can
  still report send outcomes for data already handed to it.

  Entered when stallion starts a close. Left when net reports the connection
  closed. Also left when net reports a start failure:
  `HTTPServer._on_start_failure` sets `_Closed` directly rather than routing
  through this state machine.

  Send outcomes, net's report that the connection closed, and the actor's own
  timer are all handled here. The timer matters: this state can last as long as
  the peer takes to close its half, and an actor that set a deadline with
  `HTTPServer.set_timer()` has no other way to hear from the connection until
  `on_closed()`. Everything else is a no-op.
  """

  fun ref on_received(server: HTTPServer ref, data: Array[U8] iso) =>
    None

  fun ref on_closed(server: HTTPServer ref) =>
    server._handle_closed()

  fun ref on_throttled(server: HTTPServer ref) =>
    None

  fun ref on_unthrottled(server: HTTPServer ref) =>
    None

  fun ref on_sent(server: HTTPServer ref, token: SendToken) =>
    server._handle_sent(token)

  fun ref on_send_failed(server: HTTPServer ref, token: SendToken) =>
    server._handle_send_failed(token)

  fun ref on_idle_timeout(server: HTTPServer ref) =>
    None

  fun ref on_timer(server: HTTPServer ref, token: TimerToken) =>
    server._handle_timer(token)

  fun ref on_idle_timer_failure(server: HTTPServer ref) =>
    None

  fun ref on_timer_failure(server: HTTPServer ref) =>
    server._handle_timer_failure()

  fun ref close(server: HTTPServer ref) =>
    None

class ref _Closed is _ConnectionState
  """
  Connection is closed — all operations are no-ops.
  """

  fun ref on_received(server: HTTPServer ref, data: Array[U8] iso) =>
    None

  fun ref on_closed(server: HTTPServer ref) =>
    None

  fun ref on_throttled(server: HTTPServer ref) =>
    None

  fun ref on_unthrottled(server: HTTPServer ref) =>
    None

  fun ref on_sent(server: HTTPServer ref, token: SendToken) =>
    None

  fun ref on_send_failed(server: HTTPServer ref, token: SendToken) =>
    None

  fun ref on_idle_timeout(server: HTTPServer ref) =>
    None

  fun ref on_timer(server: HTTPServer ref, token: TimerToken) =>
    None

  fun ref on_idle_timer_failure(server: HTTPServer ref) =>
    None

  fun ref on_timer_failure(server: HTTPServer ref) =>
    None

  fun ref close(server: HTTPServer ref) =>
    None
