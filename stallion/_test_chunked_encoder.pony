use "pony_check"
use "pony_test"

class \nodoc\ iso _PropertyChunkedEncoderFormat
  is Property1[Array[U8] val]
  """
  Chunked encoding produces valid wire format: hex size prefix,
  CRLF delimiters, data preserved exactly, and declared size matches
  actual data size.
  """
  fun name(): String => "chunked-encoder/format"

  fun gen(): Generator[Array[U8] val] =>
    Generators.array_of[U8](Generators.u8()
      where min = 1, max = 200)
      .map[Array[U8] val](
        {(a: Array[U8] ref): Array[U8] val =>
          var result = recover iso Array[U8](a.size()) end
          var i: USize = 0
          while i < a.size() do
            try result.push(a(i)?) end
            i = i + 1
          end
          consume result
        })

  fun ref property(arg1: Array[U8] val, ph: PropertyHelper) =>
    let encoded = _ChunkedEncoder.chunk(arg1)
    let encoded_val: Array[U8] val = consume encoded

    // Find first \r\n — separates hex size from data
    var crlf_pos: USize = 0
    var found = false
    while crlf_pos < (encoded_val.size() - 1) do
      try
        if (encoded_val(crlf_pos)? == '\r')
          and (encoded_val(crlf_pos + 1)? == '\n')
        then
          found = true
          break
        end
      end
      crlf_pos = crlf_pos + 1
    end
    ph.assert_true(found, "No CRLF found in encoded chunk")

    // Extract hex size string and verify it matches data size
    let hex_str = recover val
      let s = String.create(crlf_pos)
      var i: USize = 0
      while i < crlf_pos do
        try s.push(encoded_val(i)?) end
        i = i + 1
      end
      s
    end
    try
      let declared_size = hex_str.read_int[USize](0, 16)?._1
      ph.assert_eq[USize](arg1.size(), declared_size,
        "Declared hex size doesn't match actual data size")
    else
      ph.fail("Failed to parse hex size: " + hex_str)
    end

    // Verify data bytes are preserved
    let data_start = crlf_pos + 2  // after first \r\n
    var j: USize = 0
    while j < arg1.size() do
      try
        ph.assert_eq[U8](arg1(j)?, encoded_val(data_start + j)?,
          "Data byte mismatch at position " + j.string())
      else
        ph.fail("Index out of bounds at position " + j.string())
      end
      j = j + 1
    end

    // Verify trailing \r\n
    let trail_start = data_start + arg1.size()
    try
      ph.assert_eq[U8]('\r', encoded_val(trail_start)?,
        "Missing trailing \\r")
      ph.assert_eq[U8]('\n', encoded_val(trail_start + 1)?,
        "Missing trailing \\n")
    else
      ph.fail("Encoded chunk too short for trailing CRLF")
    end

    // Verify total size
    ph.assert_eq[USize](
      hex_str.size() + 2 + arg1.size() + 2,
      encoded_val.size(),
      "Total encoded size mismatch")

class \nodoc\ iso _TestChunkedEncoderKnownInputs is UnitTest
  """
  Verify chunked encoding with known inputs and expected outputs.
  """
  fun name(): String => "chunked-encoder/known inputs"

  fun apply(h: TestHelper) =>
    // "Hello" -> "5\r\nHello\r\n"
    let hello = _ChunkedEncoder.chunk("Hello")
    let hello_val: Array[U8] val = consume hello
    let hello_str = String.from_array(hello_val)
    h.assert_eq[String val]("5\r\nHello\r\n", hello_str)

    // Single byte
    let one = _ChunkedEncoder.chunk("X")
    let one_val: Array[U8] val = consume one
    let one_str = String.from_array(one_val)
    h.assert_eq[String val]("1\r\nX\r\n", one_str)

    // 16 bytes (hex "10")
    let sixteen = "0123456789ABCDEF"
    let enc16 = _ChunkedEncoder.chunk(sixteen)
    let enc16_val: Array[U8] val = consume enc16
    let enc16_str = String.from_array(enc16_val)
    h.assert_eq[String val]("10\r\n0123456789ABCDEF\r\n", enc16_str)

    // Final chunk
    h.assert_eq[String val]("0\r\n\r\n", _ChunkedEncoder.final_chunk())

    // Array[U8] val input
    let bytes: Array[U8] val = [as U8: 'A'; 'B'; 'C']
    let enc_bytes = _ChunkedEncoder.chunk(bytes)
    let enc_bytes_val: Array[U8] val = consume enc_bytes
    let enc_bytes_str = String.from_array(enc_bytes_val)
    h.assert_eq[String val]("3\r\nABC\r\n", enc_bytes_str)
