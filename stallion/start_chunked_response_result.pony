interface val _StartChunkedResponseResult is Stringable

primitive StreamingStarted is _StartChunkedResponseResult
  """Chunked streaming response was successfully started."""
  fun string(): String iso^ => "StreamingStarted".clone()

primitive AlreadyResponded is _StartChunkedResponseResult
  """A response has already been started or completed for this request."""
  fun string(): String iso^ => "AlreadyResponded".clone()

primitive ChunkedNotSupported is _StartChunkedResponseResult
  """
  The request uses HTTP/1.0, which does not support chunked transfer encoding.

  Use `respond()` with a `ResponseBuilder`-constructed response instead.
  """
  fun string(): String iso^ => "ChunkedNotSupported".clone()

primitive ConnectionClosed is _StartChunkedResponseResult
  """
  The connection is closed or closing, so nothing more can be sent for this
  request.

  Nothing was started: a second `start_chunked_response()` on the same
  `Responder` returns `ConnectionClosed` again, and a later `send_chunk()`
  returns `None`.
  """
  fun string(): String iso^ => "ConnectionClosed".clone()

type StartChunkedResponseResult is
  ((StreamingStarted | AlreadyResponded | ChunkedNotSupported
  | ConnectionClosed) & _StartChunkedResponseResult)
  """
  Result of `Responder.start_chunked_response()`: streaming started, or the
  reason it did not — HTTP/1.0 does not support chunked transfer encoding, a
  response was already started or completed, or the connection is closed or
  closing.
  """
