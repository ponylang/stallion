use lori = "lori"

trait tag HTTPServerActor[TCP: lori.TCPBackend ref = lori.RuntimeBackend] is
  (lori.TCPConnectionActor[TCP] & HTTPServerLifecycleEventReceiver)
  """
  Trait for actors that serve HTTP connections.

  Extends `TCPConnectionActor` (for lori ASIO plumbing) and
  `HTTPServerLifecycleEventReceiver` (for HTTP-level callbacks). The
  actor stores an `HTTPServer` as a field and implements
  `_http_connection()` to return it. All other required methods have
  default implementations that delegate to the protocol.

  Minimal implementation:

  ```pony
  actor MyServer is HTTPServerActor
    var _http: HTTPServer = HTTPServer.none()

    new create(auth: lori.TCPServerAuth, fd: U32,
      config: ServerConfig)
    =>
      _http = HTTPServer(auth, fd, this, config)

    fun ref _http_connection(): HTTPServer => _http

    fun ref on_request_complete(request': Request val,
      responder: Responder)
    =>
      // build and send response using request' and responder
  ```

  For HTTPS, use `HTTPServer.ssl(auth, ssl_ctx, fd, this, config)`
  instead of `HTTPServer(auth, fd, this, config)`.

  The `none()` default ensures all fields are initialized before the
  constructor body runs, so `this` is `ref` when passed to
  `HTTPServer.create()` or `HTTPServer.ssl()`.

  The `TCP` type parameter matches lori's `TCPConnection[TCP]` backend.
  Leave it defaulted; it exists primarily for stallion's own pure-test
  suite, which substitutes a fake backend.
  """

  fun ref _http_connection(): HTTPServer[TCP]
    """
    Return the protocol instance owned by this actor.

    Called by the default implementation of `_connection()`. Must return
    the same instance every time.
    """

  fun ref _connection(): lori.TCPConnection[TCP] =>
    """
    Delegates to the protocol's TCP connection.
    """
    _http_connection()._connection()
