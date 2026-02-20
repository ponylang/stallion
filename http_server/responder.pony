type _ResponderState is
  (_ResponderNotResponded | _ResponderStreaming | _ResponderComplete)

primitive _ResponderNotResponded
primitive _ResponderStreaming
primitive _ResponderComplete

class ref Responder
  """
  Sends an HTTP response for a single request.

  Each request receives its own `Responder`, delivered via both
  `HTTPServerLifecycleEventReceiver.request()` and
  `request_complete()`. The Responder
  buffers response data through the connection's response queue, which
  ensures pipelined responses are sent in request order.

  Two response modes are available:

  **Complete response** — build the full response with `ResponseBuilder`
  and send it via `respond()`:
  ```pony
  let body: String val = "Hello!"
  let response = ResponseBuilder(StatusOK)
    .add_header("Content-Length", body.size().string())
    .finish_headers()
    .add_chunk(body)
    .build()
  responder.respond(response)
  ```

  **Streaming response** — use chunked transfer encoding for large or
  incrementally-generated bodies:
  ```pony
  responder.start_chunked_response(StatusOK, headers)
  responder.send_chunk("chunk 1")
  responder.send_chunk("chunk 2")
  responder.finish_response()
  ```

  Responders are created internally by `HTTPServer`. Application
  code should not attempt to construct them directly.
  """
  let _queue: _ResponseQueue ref
  let _id: U64
  let _version: Version
  var _state: _ResponderState = _ResponderNotResponded

  new _create(queue: _ResponseQueue ref, id: U64, version: Version) =>
    """Create a responder for the given request."""
    _queue = queue
    _id = id
    _version = version

  fun ref respond(raw: ByteSeq) =>
    """
    Send a pre-serialized HTTP response, bypassing internal serialization.

    The `raw` bytes must be a complete HTTP response: status line, headers,
    blank line separator, and optional body. No headers are injected and no
    validation is performed — the caller is fully responsible for correct
    HTTP formatting. Use `ResponseBuilder` to construct well-formed raw
    responses.

    Only valid when no response has been started. Subsequent calls are
    silently ignored (both after `respond()` and after any other
    response method).
    """
    match _state
    | _ResponderNotResponded =>
      _state = _ResponderComplete
      _queue.send_data(_id, raw)
      _queue.finish(_id)
    end

  fun ref start_chunked_response(
    status: Status,
    headers: (Headers val | None) = None)
  =>
    """
    Begin a streaming response using chunked transfer encoding.

    Sends the status line and headers immediately (with
    `Transfer-Encoding: chunked` added automatically). Follow with
    `send_chunk()` calls and a final `finish_response()`.

    Silently ignored for HTTP/1.0 requests, which do not support chunked
    transfer encoding. Use `respond()` with a `ResponseBuilder`-
    constructed response instead.

    Only valid when no response has been started. Subsequent calls are
    silently ignored.
    """
    match _state
    | _ResponderNotResponded =>
      // HTTP/1.0 does not support chunked transfer encoding
      if _version is HTTP10 then return end

      _state = _ResponderStreaming
      let h: Headers val = recover val
        let new_h = Headers
        match headers
        | let existing: Headers val =>
          for (name, value) in existing.values() do
            new_h.set(name, value)
          end
        end
        new_h.set("Transfer-Encoding", "chunked")
        new_h
      end
      let response = _ResponseSerializer(status, h, None, _version)
      _queue.send_data(_id, consume response)
    end

  fun ref send_chunk(data: ByteSeq) =>
    """
    Send a chunk of response body data.

    The data is wrapped in chunked transfer encoding format. Empty data is
    silently ignored — use `finish_response()` to send the terminal chunk.

    Only valid after `start_chunked_response()`. Calls in other states are
    silently ignored.
    """
    match _state
    | _ResponderStreaming =>
      let size: USize = match data
      | let s: String val => s.size()
      | let a: Array[U8] val => a.size()
      end
      if size == 0 then return end
      let chunk = _ChunkedEncoder.chunk(data)
      _queue.send_data(_id, consume chunk)
    end

  fun ref finish_response() =>
    """
    Finish a streaming response by sending the terminal chunk.

    Only valid after `start_chunked_response()`. Calls in other states are
    silently ignored.
    """
    match _state
    | _ResponderStreaming =>
      _state = _ResponderComplete
      _queue.send_data(_id, _ChunkedEncoder.final_chunk())
      _queue.finish(_id)
    end
