use lori = "lori"
use ssl_net = "ssl/net"
use "time"

actor Server is lori.TCPListenerActor
  """
  HTTP server that listens for connections and dispatches requests to
  application handlers.

  Each accepted connection creates a new handler via the provided factory.
  Pass a `HandlerFactory` for buffered request bodies (common case) or a
  `StreamingHandlerFactory` for incremental body delivery. Handlers run
  synchronously inside the connection actor — no extra actor hops.

  ```pony
  use "http_server"
  use lori = "lori"

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      let config = ServerConfig("localhost", "8080")
      Server(auth, MyHandlerFactory, config)
  ```

  For HTTPS, pass an `SSLContext val`:

  ```pony
  use "http_server"
  use "files"
  use "ssl/net"
  use lori = "lori"

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      let sslctx = recover val
        SSLContext
          .> set_cert(
            FilePath(FileAuth(env.root), "cert.pem"),
            FilePath(FileAuth(env.root), "key.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end
      let config = ServerConfig("localhost", "8443")
      Server(auth, MyHandlerFactory, config where ssl_ctx = sslctx)
  ```
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _handler_factory: AnyHandlerFactory
  let _server_auth: lori.TCPServerAuth
  let _config: ServerConfig
  let _notify: (ServerNotify | None)
  let _ssl_ctx: (ssl_net.SSLContext val | None)
  let _timers: (Timers | None)

  new create(
    auth: lori.TCPListenAuth,
    handler_factory: AnyHandlerFactory,
    config: ServerConfig,
    notify: (ServerNotify | None) = None,
    ssl_ctx: (ssl_net.SSLContext val | None) = None)
  =>
    """
    Start an HTTP server listening on the configured host and port.

    The `handler_factory` creates a new handler for each accepted
    connection. Pass a `HandlerFactory` for buffered request bodies or a
    `StreamingHandlerFactory` for incremental body delivery. The factory
    must be `val` (immutable and shareable). The optional `notify` receives
    lifecycle callbacks (listening, listen failure).

    Pass an `SSLContext val` to enable HTTPS. Lori handles the SSL
    handshake, encryption, and decryption transparently — handlers see
    no difference between HTTP and HTTPS connections. If SSL session
    creation fails for a connection, the connection closes without
    notifying the handler (via lori's `_on_start_failure` path).
    """
    _handler_factory = handler_factory
    _config = config
    _notify = notify
    _ssl_ctx = ssl_ctx
    _server_auth = lori.TCPServerAuth(auth)
    _timers = if config.idle_timeout > 0 then Timers else None end
    _tcp_listener = lori.TCPListener(
      auth, config.host, config.port, this, config.max_concurrent_connections)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _Connection =>
    match _ssl_ctx
    | let ctx: ssl_net.SSLContext val =>
      _Connection.ssl_create(
        _server_auth, ctx, fd, _handler_factory, _config, _timers)
    else
      _Connection(_server_auth, fd, _handler_factory, _config, _timers)
    end

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
