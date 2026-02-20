class val ChunkSendToken is Equatable[ChunkSendToken]
  """
  Identifies a `send_chunk()` operation.

  Returned by `Responder.send_chunk()` on success and delivered to
  `HTTPServerLifecycleEventReceiver.on_chunk_sent()` when the chunk data has
  been fully handed to the OS. Tokens use structural equality based on
  their ID, which is scoped per connection.

  Applications managing multiple connections should pair tokens with
  connection identity to avoid ambiguity.
  """
  let id: U64

  new val _create(id': U64) =>
    """Create a token with the given ID. Package-private."""
    id = id'

  fun eq(that: box->ChunkSendToken): Bool =>
    id == that.id

  fun ne(that: box->ChunkSendToken): Bool =>
    not eq(that)
