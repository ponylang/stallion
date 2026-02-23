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

type StartChunkedResponseResult is
  ((StreamingStarted | AlreadyResponded | ChunkedNotSupported)
  & _StartChunkedResponseResult)
  """
  Result of calling `Responder.start_chunked_response()`: indicates whether
  streaming was started, was rejected because HTTP/1.0 doesn't support chunked
  transfer encoding, or was rejected because a response was already in progress.
  """
