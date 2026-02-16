interface val ServerNotify
  """
  Notifications for server lifecycle events.

  Implement this to be notified when the server starts listening or fails to
  start. Both callbacks default to no-ops.

  ```pony
  class val MyNotify is ServerNotify
    let _env: Env
    new val create(env: Env) => _env = env
    fun listening(server: Server tag) =>
      _env.out.print("Listening")
    fun listen_failure(server: Server tag) =>
      _env.out.print("Failed to start")
  ```
  """

  fun listening(server: Server tag) =>
    """Called when the server is listening and ready to accept connections."""
    None

  fun listen_failure(server: Server tag) =>
    """Called when the server failed to bind to the configured address."""
    None
