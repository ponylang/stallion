interface ref ResponseBuilderHeaders
  """
  Header construction phase of `ResponseBuilder`.

  Add headers with `add_header()`, then call `finish_headers()` to transition
  to the body phase. Headers are serialized in the order they are added.
  """

  fun ref add_header(name: String, value: String): ResponseBuilderHeaders
    """
    Add a header to the response.

    Headers are written in the order added. The caller is responsible for
    setting any required headers (including `Content-Length`).
    """

  fun ref finish_headers(): ResponseBuilderBody
    """
    Finish the header section and transition to the body phase.

    Writes the blank line that separates headers from the body.
    """

interface ref ResponseBuilderBody
  """
  Body construction phase of `ResponseBuilder`.

  Add body data with `add_chunk()`, then call `build()` to produce the
  final serialized response bytes.
  """

  fun ref add_chunk(data: ByteSeq): ResponseBuilderBody
    """
    Append body data to the response.

    Multiple chunks are concatenated in order. For responses with no body,
    call `build()` directly without calling `add_chunk()`.
    """

  fun ref build(): Array[U8] val
    """
    Produce the complete serialized HTTP response as an immutable byte array.

    The result is suitable for caching and reuse across multiple requests via
    `Responder.respond()`.

    Consumes the internal buffer — a second call returns an empty array.
    """

primitive ResponseBuilder
  """
  Build a complete HTTP response as a pre-serialized byte array.

  The builder uses a typed state machine to ensure responses are constructed
  in the correct order: status line, then headers, then body. Each phase
  returns an interface that exposes only the methods valid for that phase.

  The caller is responsible for all response formatting, including setting
  `Content-Length` or any other required headers. No headers are injected
  automatically.

  ```pony
  let body: String val = "Hello, World!"
  let response: Array[U8] val = ResponseBuilder(StatusOK)
    .add_header("Content-Type", "text/plain")
    .add_header("Content-Length", body.size().string())
    .finish_headers()
    .add_chunk(body)
    .build()

  // Later, in request_complete:
  responder.respond(response)
  ```

  For use in a `val` factory, wrap the builder in a `recover val` block:

  ```pony
  _cached = recover val
    ResponseBuilder(StatusOK)
      .add_header("Content-Length", "2")
      .finish_headers()
      .add_chunk("OK")
      .build()
  end
  ```
  """

  fun apply(
    status: Status,
    version: Version = HTTP11)
    : ResponseBuilderHeaders
  =>
    """Create a builder with the given status and version."""
    _ResponseBuilderImpl._create(status, version)

class ref _ResponseBuilderImpl is (ResponseBuilderHeaders & ResponseBuilderBody)
  var _buf: Array[U8] iso

  new ref _create(status: Status, version: Version) =>
    _buf = recover iso
      Array[U8].>append(version.string())
        .>push(' ')
        .>append(status.code().string())
        .>push(' ')
        .>append(status.reason())
        .>append("\r\n")
    end

  fun ref add_header(name: String, value: String): ResponseBuilderHeaders =>
    _buf.>append(name)
      .>append(": ")
      .>append(value)
      .>append("\r\n")
    this

  fun ref finish_headers(): ResponseBuilderBody =>
    _buf.append("\r\n")
    this

  fun ref add_chunk(data: ByteSeq): ResponseBuilderBody =>
    match data
    | let s: String val => _buf.append(s)
    | let a: Array[U8] val => _buf.append(a)
    end
    this

  fun ref build(): Array[U8] val =>
    (_buf = recover iso Array[U8] end)
