trait ref _ConnectionState
  """
  Connection lifecycle state.

  Dispatches lori events to the appropriate connection methods based on
  what operations are valid in each state. Phase 3 has two states:
  `_Active` (processing requests) and `_Closed` (all operations are
  no-ops). Phase 4 can split `_Active` into finer-grained states for
  keep-alive.
  """

  fun ref on_received(conn: _Connection ref, data: Array[U8] iso)
    """Handle incoming data from the TCP connection."""

  fun ref on_closed(conn: _Connection ref)
    """Handle connection close notification."""

class ref _Active is _ConnectionState
  """
  Connection is active — parsing requests and dispatching to the handler.
  """

  fun ref on_received(conn: _Connection ref, data: Array[U8] iso) =>
    conn._feed_parser(consume data)

  fun ref on_closed(conn: _Connection ref) =>
    conn._handle_closed()

class ref _Closed is _ConnectionState
  """
  Connection is closed — all operations are no-ops.
  """

  fun ref on_received(conn: _Connection ref, data: Array[U8] iso) =>
    None

  fun ref on_closed(conn: _Connection ref) =>
    None
