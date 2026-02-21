primitive _ResponseSerializer
  """
  Serialize HTTP response components into wire format bytes.

  Produces the standard HTTP/1.x response format:
  ```
  HTTP/1.1 200 OK\r\n
  header-name: value\r\n
  \r\n
  <body bytes>
  ```
  """

  fun apply(
    status: Status,
    headers: Headers val,
    body: (ByteSeq | None) = None,
    version: Version = HTTP11)
    : Array[U8] iso^
  =>
    """Serialize a response to wire format bytes."""
    recover iso
      let buf = Array[U8]

      // Status line: "HTTP/1.1 200 OK\r\n"
      buf.>append(version.string())
        .>push(' ')
        .>append(status.code().string())
        .>push(' ')
        .>append(status.reason())
        .>append("\r\n")

      // Headers
      for (name, value) in headers.values() do
        buf.>append(name)
          .>append(": ")
          .>append(value)
          .>append("\r\n")
      end

      // Blank line separating headers from body
      buf.append("\r\n")

      // Body
      match body
      | let b: String val => buf.append(b)
      | let b: Array[U8] val => buf.append(b)
      end

      buf
    end
