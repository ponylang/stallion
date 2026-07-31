class val ChunkSendToken is Equatable[ChunkSendToken]
  """
  Identifies a `send_chunk()` operation.

  Returned by `Responder.send_chunk()` on success. The same token reaches
  `HTTPServerLifecycleEventReceiver.on_chunk_sent()`. No callback fires until
  the chunk's bytes reach the OS, and even then it can be lost — see that
  callback for the case where it does not arrive. Tokens use structural
  equality based on their ID, which is scoped per connection.

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
