use "format"

primitive _ChunkedEncoder
  """
  Encode body data in HTTP chunked transfer encoding.

  Each body chunk is wrapped with a hex size prefix and CRLF delimiters.
  A zero-length terminal chunk signals the end of the response body.

  Wire format per chunk: `{hex-size}\r\n{data}\r\n`
  Terminal chunk: `0\r\n\r\n`
  """

  fun chunk(data: ByteSeq): Array[U8] iso^ =>
    """
    Wrap data in chunked encoding: `{hex-size}\r\n{data}\r\n`.

    The caller must not pass empty data — use `final_chunk()` for the
    terminal chunk instead.
    """
    let size: USize = match \exhaustive\ data
    | let s: String val => s.size()
    | let a: Array[U8] val => a.size()
    end
    let hex: String val = Format.int[USize](size where fmt = FormatHexBare)
    recover iso
      let buf = Array[U8](hex.size() + 2 + size + 2)
      buf.>append(hex)
        .>append("\r\n")
        .>append(data)
        .>append("\r\n")
      buf
    end

  fun final_chunk(): String val =>
    """Terminal chunk marking end of chunked body."""
    "0\r\n\r\n"
