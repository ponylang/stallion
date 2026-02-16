use lori = "lori"

actor _Connection is
  (lori.TCPConnectionActor & lori.ServerLifecycleEventReceiver
    & _RequestParserNotify)
  """
  Per-connection actor that owns TCP I/O, parsing, handler dispatch,
  and response sending.

  Implements the single-actor connection model: no actor boundaries
  between the TCP layer and application handler. Data arrives via
  `_on_received`, is fed to the parser, and parser callbacks are
  forwarded to the handler synchronously.

  Phase 3 lifecycle: close after every response. No keep-alive.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Active
  let _responder: Responder
  let _handler: Handler
  var _parser: (_RequestParser | None) = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    handler_factory: HandlerFactory)
  =>
    // Initialize responder and handler first with placeholder connection.
    // _parser defaults to None, so all fields are now initialized and
    // `this` becomes `ref` — required by TCPConnection.server and
    // _RequestParser.
    _responder = Responder._create(_tcp_connection)
    _handler = handler_factory(_responder)
    _tcp_connection = lori.TCPConnection.server(auth, fd, this, this)
    _responder._set_connection(_tcp_connection)
    _parser = _RequestParser(this)

  //
  // TCPConnectionActor / ServerLifecycleEventReceiver
  //

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _state.on_received(this, consume data)

  fun ref _on_closed() =>
    _state.on_closed(this)

  //
  // _RequestParserNotify — forwarding parser events to handler
  //

  fun ref request_received(
    method: Method,
    uri: String val,
    version: Version,
    headers: Headers val)
  =>
    _responder._set_version(version)
    _handler.request(method, uri, version, headers)

  fun ref body_chunk(data: Array[U8] val) =>
    _handler.body_chunk(data)

  fun ref request_complete() =>
    _handler.request_complete()
    // Phase 3: always close after request completes
    _tcp_connection.close()
    _state = _Closed

  fun ref parse_error(err: ParseError) =>
    let response = _ResponseSerializer(
      StatusBadRequest,
      recover val Headers end)
    _tcp_connection.send(consume response)
    _tcp_connection.close()
    _state = _Closed

  //
  // Internal methods called by state classes
  //

  fun ref _feed_parser(data: Array[U8] iso) =>
    """Feed incoming data to the request parser."""
    match _parser
    | let p: _RequestParser => p.parse(consume data)
    end

  fun ref _handle_closed() =>
    """Notify the handler that the connection has closed."""
    _handler.closed()
    _state = _Closed
