use "pony_test"

// ---------------------------------------------------------------------------
// Cross-position parity matrix (Discussion #123 §1e).
//
// For each malformed-byte class, assert rejection at EVERY position it can
// appear: request line, header name, header value, chunk-size line, chunk
// extension, trailer name, trailer value. This is the direct antidote to "the
// field-value fix never reached trailers" — a class fixed at one position but
// not another shows up here as a single failing cell.
//
// Reuses the `_Case` / `_CaseRunner` machinery from the conformance corpus.
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRequestParity is UnitTest
  fun name(): String => "parser/parity_matrix"

  fun apply(h: TestHelper) =>
    for c in _ParityCases.all().values() do
      _CaseRunner.run(h, c)
    end

primitive \nodoc\ _ParityCases
  fun all(): Array[_Case] val =>
    let out = recover iso Array[_Case] end
    for c in bare_cr().values() do out.push(c) end
    for c in bare_lf().values() do out.push(c) end
    for c in non_token_name().values() do out.push(c) end
    for c in nul_in_value().values() do out.push(c) end
    consume out

  fun bare_cr(): Array[_Case] val =>
    """A lone CR (not followed by LF) at each position → BareCRLF."""
    [ _Case("parity_cr_request_line",
        "GET /a\rb HTTP/1.1\r\nHost: a\r\n\r\n", BareCRLF)
      _Case("parity_cr_header_name",
        "GET / HTTP/1.1\r\nHost: a\r\nX\rY: v\r\n\r\n", BareCRLF)
      _Case("parity_cr_header_value",
        "GET / HTTP/1.1\r\nHost: a\r\nX: a\rb\r\n\r\n", BareCRLF)
      _Case("parity_cr_chunk_size",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\rx\r\n01234\r\n0\r\n\r\n", BareCRLF)
      _Case("parity_cr_chunk_ext",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a\rb\r\n01234\r\n0\r\n\r\n", BareCRLF)
      _Case("parity_cr_trailer_name",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX\rY: v\r\n\r\n", BareCRLF)
      _Case("parity_cr_trailer_value",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX: a\rb\r\n\r\n", BareCRLF)
    ]

  fun bare_lf(): Array[_Case] val =>
    """A lone LF (not preceded by CR) at each position → BareCRLF."""
    [ _Case("parity_lf_request_line",
        "GET /a\nb HTTP/1.1\r\nHost: a\r\n\r\n", BareCRLF)
      _Case("parity_lf_header_name",
        "GET / HTTP/1.1\r\nHost: a\r\nX\nY: v\r\n\r\n", BareCRLF)
      _Case("parity_lf_header_value",
        "GET / HTTP/1.1\r\nHost: a\r\nX: a\nb\r\n\r\n", BareCRLF)
      _Case("parity_lf_chunk_size",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\nx\r\n01234\r\n0\r\n\r\n", BareCRLF)
      _Case("parity_lf_chunk_ext",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a\nb\r\n01234\r\n0\r\n\r\n", BareCRLF)
      _Case("parity_lf_trailer_name",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX\nY: v\r\n\r\n", BareCRLF)
      _Case("parity_lf_trailer_value",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX: a\nb\r\n\r\n", BareCRLF)
    ]

  fun non_token_name(): Array[_Case] val =>
    """
    A non-token character in a name position. A non-token method is a malformed
    request line (InvalidRequestLine); header and trailer names → InvalidFieldName.
    """
    [ _Case("parity_nontoken_method",
        "GE@T / HTTP/1.1\r\nHost: a\r\n\r\n", InvalidRequestLine)
      _Case("parity_nontoken_header_name",
        "GET / HTTP/1.1\r\nHost: a\r\nX@Y: v\r\n\r\n", InvalidFieldName)
      _Case("parity_nontoken_trailer_name",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX@Y: v\r\n\r\n", InvalidFieldName)
    ]

  fun nul_in_value(): Array[_Case] val =>
    """A NUL byte in a value position → InvalidFieldValue (header and trailer)."""
    [ _Case("parity_nul_header_value",
        "GET / HTTP/1.1\r\nHost: a\r\nX: a\x00b\r\n\r\n", InvalidFieldValue)
      _Case("parity_nul_trailer_value",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX: a\x00b\r\n\r\n", InvalidFieldValue)
    ]

// ---------------------------------------------------------------------------
// Bare-CR/LF injection sweep (Discussion #123 §1e).
//
// Insert a single bare CR or bare LF at every offset within the framing region
// of a well-formed, body-less request. The parser must NEVER deliver a
// completed request with the byte silently folded in — it must reject or stay
// incomplete. A folded-and-completed request is a smuggling desync, recorded
// here as a violation.
//
// Exhaustive over offsets (stronger than random sampling). The template has no
// body, so completion is all-or-nothing; the trailing CRLF terminator is left
// out of the injection range (a byte after it is a legitimate next-request
// prefix, not a fold).
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestBareCRLFInjection is UnitTest
  fun name(): String => "parser/bare_crlf_injection"

  fun apply(h: TestHelper) =>
    let template = "GET / HTTP/1.1\r\nHost: a\r\nX: y\r\n\r\n"
    let base: Array[U8] val = template.array()
    // Leave the final CRLF (the empty-line terminator) out of the range.
    let limit = base.size() - 2
    var violations: USize = 0
    var first_offset: USize = 0
    var first_byte: U8 = 0

    for b in [as U8: '\r'; '\n'].values() do
      var at: USize = 0
      while at < limit do
        let notify: _TestParserNotify ref = _TestParserNotify
        let parser = _RequestParser(notify)
        parser.parse(_inject(base, at, b))
        if notify.completed != 0 then
          if violations == 0 then
            first_offset = at
            first_byte = b
          end
          violations = violations + 1
        end
        at = at + 1
      end
    end

    h.assert_eq[USize](0, violations,
      "bare CR/LF folded into a completed request in " + violations.string() +
      " of " + (limit * 2).string() + " injections; first at offset " +
      first_offset.string() + " byte 0x" + _hex(first_byte))

  fun _inject(base: Array[U8] val, at: USize, b: U8): Array[U8] iso^ =>
    """Return a copy of `base` with byte `b` inserted before index `at`."""
    let out = recover Array[U8](base.size() + 1) end
    var i: USize = 0
    while i < base.size() do
      if i == at then out.push(b) end
      try out.push(base(i)?) end
      i = i + 1
    end
    out

  fun _hex(b: U8): String =>
    let digits = "0123456789abcdef"
    let s = recover String(2) end
    try s.push(digits(((b and 0xF0) >> 4).usize())?) end
    try s.push(digits((b and 0x0F).usize())?) end
    consume s
