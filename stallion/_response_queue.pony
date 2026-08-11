type _QueueResult is (_QueueAccepted | _QueueEntryGone)

primitive _QueueAccepted
primitive _QueueEntryGone

class ref _QueueEntry
  """
  Per-request buffered response data.
  """
  let keep_alive: Bool
  embed data: Array[ByteSeq] ref
  embed tokens: Array[(ChunkSendToken | None)] ref
  var finished: Bool = false

  new create(keep_alive': Bool) =>
    keep_alive = keep_alive'
    data = Array[ByteSeq]
    tokens = Array[(ChunkSendToken | None)]

class ref _ResponseQueue
  """
  Buffers pipelined responses and flushes them in request order.

  Each request is registered via `register()` which assigns a monotonically
  increasing ID. Response data is submitted via `send_data()` and completed
  via `finish()`. The queue ensures data reaches the TCP connection in
  registration order, regardless of the order actors respond.

  For the head-of-line entry, data is sent immediately via the notify
  callback (unless throttled). For non-head entries, data is buffered until
  the entry becomes the head.

  The queue carries no connection-lifecycle state. `close()` is pure
  teardown: it clears entries, and subsequent operations report
  `_QueueEntryGone` because the entry array is empty. The connection state
  machine (`HTTPServer._state`) is the sole authority on whether the
  connection is alive.

  **Re-entrancy contract**: both `close()` and `throttle()` may be called
  from within `_flush_data`. `_flush_data` calls `TCPConnection.send()`,
  which synchronously fires `_on_throttled` (on a partial write) — that
  re-enters as `throttle()` — or, on a send error, closes the connection,
  which re-enters as `close()`. `_response_complete` may likewise re-enter
  as `close()` (e.g., keep-alive=false). `_pump_head` is the single place
  head data is flushed: it re-checks `_entries.size()` and `_throttled`
  after every `_flush_data` and in its outer loop, so a re-throttle leaves
  the unsent chunks buffered for the next `unthrottle()` and a close (which
  clears entries) stops the cascade safely.
  """
  let _notify: _ResponseQueueNotify ref
  var _head_id: U64 = 0
  var _next_id: U64 = 0
  var _next_chunk_token_id: U64 = 0
  embed _entries: Array[_QueueEntry]
  var _throttled: Bool = false

  new create(notify: _ResponseQueueNotify ref) =>
    """
    Create a response queue with the given notify callback.
    """
    _notify = notify
    _entries = Array[_QueueEntry]

  fun ref create_chunk_token(): ChunkSendToken =>
    """
    Create a new chunk send token with a unique ID.

    Called by `Responder.send_chunk()` to mint a token before submitting
    data to the queue. The token travels alongside the data through
    buffering and flushing. No callback fires until the chunk's bytes reach
    the OS, and even then it can be lost — see
    `HTTPServerLifecycleEventReceiver.on_chunk_sent()`.
    """
    let id = _next_chunk_token_id
    _next_chunk_token_id = _next_chunk_token_id + 1
    ChunkSendToken._create(id)

  fun ref register(keep_alive: Bool): U64 =>
    """
    Register a new request at the tail of the queue.

    Returns the assigned request ID. IDs are monotonically increasing
    starting from 0.
    """
    let id = _next_id
    _next_id = _next_id + 1
    _entries.push(_QueueEntry(keep_alive))
    id

  fun has_entry(id: U64): Bool =>
    """
    Check whether the entry for a request ID still exists.

    Returns `true` when the entry is present in the queue, `false` when it
    has been cleared by `close()`. Pure read — no side effects.
    """
    let index = (id - _head_id).usize()
    index < _entries.size()

  fun ref send_data(
    id: U64,
    data: ByteSeq,
    token: (ChunkSendToken | None) = None)
    : _QueueResult
  =>
    """
    Submit response data for a request.

    If the request is the head of the queue and the queue is not throttled,
    data is sent immediately via `_flush_data`. Otherwise, data is buffered
    in the entry for later flushing. The optional `token` travels alongside
    the data — `ChunkSendToken` for user chunks, `None` for internal sends.

    Returns `_QueueAccepted` when the data was buffered or sent, or
    `_QueueEntryGone` when the entry no longer exists (the queue was torn
    down by `close()`).
    """
    let index = (id - _head_id).usize()
    try
      let entry = _entries(index)?
      if (id == _head_id) and (not _throttled) then
        _notify._flush_data(data, token)
        // Re-entrant close from _flush_data may have cleared entries.
        if _entries.size() == 0 then return _QueueEntryGone end
      else
        entry.data.push(data)
        entry.tokens.push(token)
      end
      _QueueAccepted
    else
      if _entries.size() == 0 then
        _QueueEntryGone
      else
        _Unreachable()
        _QueueEntryGone
      end
    end

  fun ref finish(id: U64): _QueueResult =>
    """
    Mark a request's response as complete.

    Marks the entry finished. If it is the head, drives `_pump_head`, which
    flushes any remaining buffered data and — once the head is fully drained
    and not throttled — advances, cascading through already-complete
    pipelined entries behind it. A throttled head with buffered data is
    deferred: it stays at the head and advances on the next `unthrottle()`,
    so its data is never dropped. A non-head entry is flushed when it
    becomes the head.

    Returns `_QueueAccepted` when the entry was marked finished, or
    `_QueueEntryGone` when the entry no longer exists (the queue was torn
    down by `close()`).
    """
    let index = (id - _head_id).usize()
    try
      let entry = _entries(index)?
      entry.finished = true
      if id == _head_id then
        _pump_head()
      end
      _QueueAccepted
    else
      if _entries.size() == 0 then
        _QueueEntryGone
      else
        _Unreachable()
        _QueueEntryGone
      end
    end

  fun ref throttle() =>
    """
    Apply backpressure — buffer head data instead of sending to TCP.
    """
    _throttled = true

  fun ref unthrottle() =>
    """
    Release backpressure — flush any buffered data for the head entry.
    """
    _throttled = false
    _pump_head()

  fun ref close() =>
    """
    Discard all pending entries.

    Pure teardown — clears the entry array. Subsequent `send_data` and
    `finish` calls report `_QueueEntryGone` because the entries are gone.

    Safe to call from within `_response_complete` or `_flush_data`
    callbacks — the empty entries array stops cascading flushes in
    `_pump_head`.
    """
    _entries.clear()

  fun pending(): USize =>
    """
    Number of requests registered but not yet finished.
    """
    _entries.size()

  fun ref _advance_head() =>
    """
    Remove the current head entry and notify completion.

    Precondition: the caller has fully drained the head's buffered data and
    is not throttled. `_pump_head` is the only caller and guarantees both.
    Does NOT flush the new head — `_pump_head`'s loop re-pumps after this
    returns, so the cascade through already-complete pipelined entries
    happens in one place.
    """
    try
      let entry = _entries.shift()?
      _head_id = _head_id + 1
      _notify._response_complete(entry.keep_alive)
    else
      _Unreachable()
    end

  fun ref _pump_head() =>
    """
    Drive the head entry forward: flush its buffered data in order, and when
    the entry is fully drained and finished, advance to the next head and
    repeat (cascading flush for already-complete pipelined entries).

    THE single place head data is flushed. Stops early on:

    - entries gone (`_entries.size() == 0`) — `close()` cleared the array,
      nothing more to send;
    - re-throttle (`_throttled`) — `TCPConnection.send()`, called inside
      `_flush_data`, synchronously fires `_on_throttled` on a partial write
      / EWOULDBLOCK, which re-enters as `throttle()` and re-sets `_throttled`
      mid-loop. The remaining chunks stay buffered in `entry.data` for the
      next `unthrottle()` to resume — never dropped.

    Chunks are shifted off one at a time so survivors remain on a re-throttle
    or close. `_advance_head` is only reached here, only when the buffer is
    empty and we are not throttled.
    """
    while (not _throttled) and (_entries.size() > 0) do
      try
        let entry = _entries(0)?
        while entry.data.size() > 0 do
          try
            _notify._flush_data(entry.data.shift()?, entry.tokens.shift()?)
          else
            _Unreachable()
          end
          if (_entries.size() == 0) or _throttled then return end
        end
        if entry.finished then
          _advance_head()
        else
          return
        end
      else
        _Unreachable()
      end
    end
