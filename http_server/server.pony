use lori = "lori"
use "time"

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
      let config = ServerConfig("localhost", "8080")
      Server(auth, MyHandlerFactory, config)
  ```
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _handler_factory: HandlerFactory
  let _server_auth: lori.TCPServerAuth
  let _config: ServerConfig
  let _notify: (ServerNotify | None)
  let _timers: (Timers | None)

  new create(
    auth: lori.TCPListenAuth,
    handler_factory: HandlerFactory,
    config: ServerConfig,
    notify: (ServerNotify | None) = None)
  =>
    """
    Start an HTTP server listening on the configured host and port.

    The `handler_factory` creates a new `Handler` for each accepted
    connection. It must be `val` (immutable and shareable). The optional
    `notify` receives lifecycle callbacks (listening, listen failure).
    """
    _handler_factory = handler_factory
    _config = config
    _notify = notify
    _server_auth = lori.TCPServerAuth(auth)
    _timers = if config.idle_timeout > 0 then Timers else None end
    _tcp_listener = lori.TCPListener(
      auth, config.host, config.port, this, config.max_concurrent_connections)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _Connection =>
    _Connection(_server_auth, fd, _handler_factory, _config, _timers)

  fun ref _on_listening() =>
    match _notify
    | let n: ServerNotify => n.listening(this)
    end

  fun ref _on_listen_failure() =>
    match _notify
    | let n: ServerNotify => n.listen_failure(this)
    end

  be dispose() =>
    match _timers
    | let t: Timers => t.dispose()
    end
    _tcp_listener.close()
