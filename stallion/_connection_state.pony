use lori = "lori"

trait ref _ConnectionState
  """
  Connection lifecycle state.

  Dispatches lori events to the appropriate server methods based on
  what operations are valid in each state. Two states: `_Active`
  (processing requests, including idle keep-alive periods) and `_Closed`
  (all operations are no-ops).
  """

  fun ref on_received(server: HTTPServer ref, data: Array[U8] iso)
    """Handle incoming data from the TCP connection."""

  fun ref on_closed(server: HTTPServer ref)
    """Handle connection close notification."""

  fun ref on_throttled(server: HTTPServer ref)
    """Handle backpressure applied notification."""

  fun ref on_unthrottled(server: HTTPServer ref)
    """Handle backpressure released notification."""

  fun ref on_sent(server: HTTPServer ref, token: lori.SendToken)
    """Handle send completion notification from lori."""

  fun ref on_idle_timeout(server: HTTPServer ref)
    """Handle connection going idle."""

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

  fun ref on_sent(server: HTTPServer ref, token: lori.SendToken) =>
    server._handle_sent(token)

  fun ref on_idle_timeout(server: HTTPServer ref) =>
    server._handle_idle_timeout()

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

  fun ref on_sent(server: HTTPServer ref, token: lori.SendToken) =>
    None

  fun ref on_idle_timeout(server: HTTPServer ref) =>
    None
