class ref _BufferingAdapter is StreamingHandler
  """
  Adapts a buffered `Handler` to the `StreamingHandler` interface.

  Accumulates body chunks internally and delivers the complete body
  to the wrapped handler at `request_complete`. Used by `_Connection`
  when a `HandlerFactory` is provided, so the connection always works
  with `StreamingHandler` internally.

  The buffer resets between pipelined requests: `request_complete`
  swaps the accumulator with a fresh empty array.
  """
  let _inner: Handler
  var _body: Array[U8] iso = recover iso Array[U8] end
  var _has_body: Bool = false

  new create(inner: Handler) =>
    _inner = inner

  fun ref request(r: Request val) =>
    _inner.request(r)

  fun ref body_chunk(data: Array[U8] val) =>
    _has_body = true
    _body.append(data)

  fun ref request_complete(responder: Responder) =>
    if _has_body then
      _has_body = false
      let body: Array[U8] val =
        (_body = recover iso Array[U8] end)
      _inner.request_complete(responder, body)
    else
      _inner.request_complete(responder, None)
    end

  fun ref closed() =>
    _inner.closed()

  fun ref throttled() =>
    _inner.throttled()

  fun ref unthrottled() =>
    _inner.unthrottled()
