trait ref _ResponseQueueNotify
  """
  Callback interface for response queue events.

  The queue calls these methods during `finish()` and `send_data()` to
  delegate TCP I/O and lifecycle decisions to the connection actor. All
  calls occur synchronously within the connection actor's execution context.
  """

  fun ref _flush_data(data: ByteSeq,
    token: (ChunkSendToken | None) = None)
    """
    Send response data to the TCP connection.

    Called when data for the head-of-line entry is ready to send. The
    `token` is `ChunkSendToken` for user chunk data (from `send_chunk()`)
    or `None` for internal sends (headers, terminal chunk, complete
    responses). The implementor should call `TCPConnection.send()` and
    handle send errors (e.g., by calling `_close_connection()` which in
    turn calls `_queue.close()`).
    """

  fun ref _response_complete(keep_alive: Bool)
    """
    Called when a completed response has been fully flushed from the head
    of the queue.

    The `keep_alive` flag is the per-request keep-alive decision made at
    request parsing time. The implementor uses this to decide whether to
    close the connection or continue accepting requests.

    This method may be called multiple times in a single `finish()` call
    when cascading flushes occur (buffered entries behind the head that
    are already complete).
    """

class ref _QueueEntry
  """Per-request buffered response data."""
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

  **Re-entrancy contract**: `close()` may be called from within either
  callback — `_response_complete` (e.g., keep-alive=false triggers
  connection close) or `_flush_data` (e.g., TCP send error triggers
  connection close). The flush methods check `_closed` before each
  `_flush_data` call and before cascading into `_advance_head()`,
  stopping the cascade safely.
  """
  let _notify: _ResponseQueueNotify ref
  var _head_id: U64 = 0
  var _next_id: U64 = 0
  var _next_chunk_token_id: U64 = 0
  embed _entries: Array[_QueueEntry]
  var _throttled: Bool = false
  var _closed: Bool = false

  new create(notify: _ResponseQueueNotify ref) =>
    """Create a response queue with the given notify callback."""
    _notify = notify
    _entries = Array[_QueueEntry]

  fun ref create_chunk_token(): ChunkSendToken =>
    """
    Create a new chunk send token with a unique ID.

    Called by `Responder.send_chunk()` to mint a token before submitting
    data to the queue. The token travels alongside the data through
    buffering and flushing, ultimately reaching the actor via
    `on_chunk_sent()` when the OS accepts the bytes.
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

  fun ref send_data(id: U64, data: ByteSeq,
    token: (ChunkSendToken | None) = None)
  =>
    """
    Submit response data for a request.

    If the request is the head of the queue and the queue is not throttled,
    data is sent immediately via `_flush_data`. Otherwise, data is buffered
    in the entry for later flushing. The optional `token` travels alongside
    the data — `ChunkSendToken` for user chunks, `None` for internal sends.
    """
    if _closed then return end
    let index = (id - _head_id).usize()
    try
      let entry = _entries(index)?
      if (id == _head_id) and (not _throttled) then
        _notify._flush_data(data, token)
      else
        entry.data.push(data)
        entry.tokens.push(token)
      end
    else
      _Unreachable()
    end

  fun ref finish(id: U64) =>
    """
    Mark a request's response as complete.

    If the request is the head of the queue, notifies the connection via
    `_response_complete` and advances to the next entry, flushing any
    buffered data for entries that are already complete (cascading flush).

    The cascading flush checks `_closed` before each entry to handle
    `close()` being called from within a callback (see re-entrancy
    contract on the class docstring).
    """
    if _closed then return end
    let index = (id - _head_id).usize()
    try
      let entry = _entries(index)?
      if id == _head_id then
        // Head entry — advance
        _advance_head()
      else
        // Non-head — mark finished, will flush when it becomes head
        entry.finished = true
      end
    else
      _Unreachable()
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
    if _closed then return end
    _flush_head_buffered()

  fun ref close() =>
    """
    Discard all pending entries. All subsequent operations become no-ops.

    Safe to call from within `_response_complete` or `_flush_data`
    callbacks — the `_closed` flag stops cascading flushes.
    """
    _closed = true
    _entries.clear()

  fun pending(): USize =>
    """Number of requests registered but not yet finished."""
    _entries.size()

  fun ref _advance_head() =>
    """
    Remove the current head entry and advance to the next.

    Notifies the connection that the head response is complete, then checks
    if the new head has buffered data to flush.
    """
    try
      let entry = _entries.shift()?
      _head_id = _head_id + 1
      let keep_alive = entry.keep_alive
      _notify._response_complete(keep_alive)
      // Check closed flag — _response_complete may have triggered close
      if _closed then return end
      _flush_new_head()
    else
      _Unreachable()
    end

  fun ref _flush_new_head() =>
    """
    Flush buffered data for the new head entry and cascade if complete.
    """
    if _closed then return end
    try
      let entry = _entries(0)?
      // Send all buffered data for the new head (data and tokens in lockstep)
      var i: USize = 0
      while i < entry.data.size() do
        if _closed then return end
        try
          _notify._flush_data(entry.data(i)?, entry.tokens(i)?)
        else
          _Unreachable()
        end
        i = i + 1
      end
      entry.data.clear()
      entry.tokens.clear()
      if entry.finished and (not _closed) then
        _advance_head()
      end
    end

  fun ref _flush_head_buffered() =>
    """
    Flush buffered data for the current head entry (after unthrottle).
    """
    try
      let entry = _entries(0)?
      var i: USize = 0
      while i < entry.data.size() do
        if _closed then return end
        try
          _notify._flush_data(entry.data(i)?, entry.tokens(i)?)
        else
          _Unreachable()
        end
        i = i + 1
      end
      entry.data.clear()
      entry.tokens.clear()
      if entry.finished and (not _closed) then
        _advance_head()
      end
    end
