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
