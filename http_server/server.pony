use lori = "lori"

actor Server is lori.TCPListenerActor
  """
  HTTP server that listens for connections and dispatches requests to
  application handlers.

  Each accepted connection creates a new `Handler` via the provided
  `HandlerFactory`. Handlers run synchronously inside the connection
  actor — no extra actor hops for the common case.

  ```pony
  use "http_server"
  use lori = "lori"

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      Server(auth, "localhost", "8080", MyHandlerFactory)
  ```
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _handler_factory: HandlerFactory
  let _server_auth: lori.TCPServerAuth

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    handler_factory: HandlerFactory)
  =>
    """
    Start an HTTP server listening on the given host and port.

    The `handler_factory` creates a new `Handler` for each accepted
    connection. It must be `val` (immutable and shareable).
    """
    _handler_factory = handler_factory
    _server_auth = lori.TCPServerAuth(auth)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _Connection =>
    _Connection(_server_auth, fd, _handler_factory)
