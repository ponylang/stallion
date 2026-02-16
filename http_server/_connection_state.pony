trait ref _ConnectionState
  """
  Connection lifecycle state.

  Dispatches lori events to the appropriate connection methods based on
  what operations are valid in each state. Two states: `_Active`
  (processing requests, including idle keep-alive periods) and `_Closed`
  (all operations are no-ops).
  """

  fun ref on_received(conn: _Connection ref, data: Array[U8] iso)
    """Handle incoming data from the TCP connection."""

  fun ref on_closed(conn: _Connection ref)
    """Handle connection close notification."""

  fun ref on_throttled(conn: _Connection ref)
    """Handle backpressure applied notification."""

  fun ref on_unthrottled(conn: _Connection ref)
    """Handle backpressure released notification."""

  fun ref on_idle_timeout(conn: _Connection ref)
    """Handle idle timeout expiration."""

class ref _Active is _ConnectionState
  """
  Connection is active — parsing requests and dispatching to the handler.
  """

  fun ref on_received(conn: _Connection ref, data: Array[U8] iso) =>
    conn._feed_parser(consume data)

  fun ref on_closed(conn: _Connection ref) =>
    conn._handle_closed()

  fun ref on_throttled(conn: _Connection ref) =>
    conn._handle_throttled()

  fun ref on_unthrottled(conn: _Connection ref) =>
    conn._handle_unthrottled()

  fun ref on_idle_timeout(conn: _Connection ref) =>
    conn._handle_idle_timeout()

class ref _Closed is _ConnectionState
  """
  Connection is closed — all operations are no-ops.
  """

  fun ref on_received(conn: _Connection ref, data: Array[U8] iso) =>
    None

  fun ref on_closed(conn: _Connection ref) =>
    None

  fun ref on_throttled(conn: _Connection ref) =>
    None

  fun ref on_unthrottled(conn: _Connection ref) =>
    None

  fun ref on_idle_timeout(conn: _Connection ref) =>
    None
