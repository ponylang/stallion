use "pony_test"

// ---------------------------------------------------------------------------
// Table-driven HTTP/1.1 request conformance corpus (parser level).
//
// Each case is (name, raw-bytes, expected-outcome). Outcomes are:
//   _Accept     — request_received with the given method/target/version, the
//                 exact body bytes, and exactly one request_complete.
//   _Incomplete — the parser consumed the bytes without completing or erroring
//                 (it needs more data); no request_complete, no parse_error.
//   ParseError  — exactly one parse_error with that specific error value.
//
// Assertions target the specific dimension so flipping any case's expectation
// makes it fail (counterfactual-friendly). The harness runs every case and
// reports each failure by name, so running the corpus against a parser yields a
// failure catalogue rather than a single opaque failure.
//
// Raw bytes are authored as String literals with explicit \r\n; control bytes
// (NUL, VT) use \xNN escapes. Pony strings are length-counted, not
// NUL-terminated, so an embedded \x00 is a real byte in the request.
// ---------------------------------------------------------------------------

primitive \nodoc\ _Incomplete
  """Expected outcome: parser needs more data (no completion, no error)."""

class \nodoc\ val _Accept
  """Expected outcome: a fully parsed request with these fields."""
  let method: String
  let target: String
  let version: Version
  let body: String

  new val create(
    method': String,
    target': String,
    version': Version,
    body': String = "")
  =>
    method = method'
    target = target'
    version = version'
    body = body'

type _Expected is (_Accept | _Incomplete | ParseError)

class \nodoc\ val _Case
  let name: String
  let raw: String
  let expected: _Expected

  new val create(name': String, raw': String, expected': _Expected) =>
    name = name'
    raw = raw'
    expected = expected'

class \nodoc\ iso _TestRequestConformance is UnitTest
  """
  Runs the parser-level conformance corpus single-shot through `_RequestParser`
  and asserts each case's expected outcome. A failure names the offending case.
  """
  fun name(): String => "parser/conformance"

  fun apply(h: TestHelper) =>
    for c in _ConformanceCases.all().values() do
      _CaseRunner.run(h, c)
    end

primitive \nodoc\ _CaseRunner
  """
  Runs one conformance `_Case` single-shot through `_RequestParser` and asserts
  its expected outcome, naming the case on failure. Shared by the table corpus
  and the parity matrix.
  """
  fun run(h: TestHelper, c: _Case) =>
    let notify: _TestParserNotify ref = _TestParserNotify
    let parser = _RequestParser(notify)
    parser.parse(recover c.raw.array().clone() end)

    match c.expected
    | let a: _Accept => _assert_accept(h, c, notify, a)
    | _Incomplete => _assert_incomplete(h, c, notify)
    | let e: ParseError => _assert_reject(h, c, notify, e)
    end

  fun _assert_accept(
    h: TestHelper,
    c: _Case,
    notify: _TestParserNotify,
    a: _Accept)
  =>
    if notify.errors.size() != 0 then
      h.fail(_fail(c, "accept", _first_error(notify)))
      return
    end
    if notify.requests.size() != 1 then
      h.fail(_fail(c, "1 request",
        notify.requests.size().string() + " requests"))
      return
    end
    if notify.completed != 1 then
      h.fail(_fail(c, "1 completion",
        notify.completed.string() + " completions"))
      return
    end
    try
      (let m, let u, let v, _) = notify.requests(0)?
      if m.string() != a.method then
        h.fail(_fail(c, "method " + a.method, "method " + m.string()))
      end
      if u != a.target then
        h.fail(_fail(c, "target " + a.target, "target " + u))
      end
      if not (v is a.version) then
        h.fail(_fail(c, "version mismatch", "version mismatch"))
      end
      let got_body = notify.collected_body_string()
      if got_body != a.body then
        h.fail(_fail(c, "body '" + a.body + "'", "body '" + got_body + "'"))
      end
    else
      h.fail(_fail(c, "readable request", "unreadable request"))
    end

  fun _assert_incomplete(h: TestHelper, c: _Case, notify: _TestParserNotify) =>
    if notify.errors.size() != 0 then
      h.fail(_fail(c, "incomplete", _first_error(notify)))
    elseif notify.completed != 0 then
      h.fail(_fail(c, "incomplete", "completed"))
    end

  fun _assert_reject(
    h: TestHelper,
    c: _Case,
    notify: _TestParserNotify,
    e: ParseError)
  =>
    if notify.errors.size() != 1 then
      let got =
        if notify.errors.size() == 0 then
          if notify.completed > 0 then "accept" else "incomplete" end
        else
          notify.errors.size().string() + " errors"
        end
      h.fail(_fail(c, e.string(), got))
      return
    end
    try
      let actual = notify.errors(0)?
      if not (actual is e) then
        h.fail(_fail(c, e.string(), actual.string()))
      end
    else
      h.fail(_fail(c, e.string(), "unreadable error"))
    end

  fun _first_error(notify: _TestParserNotify): String =>
    try notify.errors(0)?.string() else "accept" end

  fun _fail(c: _Case, want: String, got: String): String =>
    "[" + c.name + "] expected " + want + ", got " + got

primitive \nodoc\ _ConformanceCases
  """
  The parser-level conformance corpus. Grouped by concern; `all()` concatenates
  every group. Protocol-layer cases (request-target structure, Host, CONNECT)
  live in the HTTPServer-level suite, not here.
  """
  fun all(): Array[_Case] val =>
    let out = recover iso Array[_Case] end
    for c in request_line().values() do out.push(c) end
    for c in header_validation().values() do out.push(c) end
    for c in content_length().values() do out.push(c) end
    for c in transfer_encoding().values() do out.push(c) end
    for c in chunked_body().values() do out.push(c) end
    for c in trailers().values() do out.push(c) end
    consume out

  fun request_line(): Array[_Case] val =>
    """
    Request line: `method SP request-target SP HTTP-version CRLF`, exactly one
    SP between components (RFC 9112 §3). `space_in_request_target` is handled
    HERE (parser level) as a framing violation, not at the protocol layer.
    """
    [ _Case("rl_simple_ok",
        "GET / HTTP/1.1\r\nHost: a\r\n\r\n",
        _Accept("GET", "/", HTTP11))
      _Case("rl_http10_ok",
        "GET / HTTP/1.0\r\nHost: a\r\n\r\n",
        _Accept("GET", "/", HTTP10))
      _Case("bare_lf_request_line",
        "GET / HTTP/1.1\nHost: a\r\n\r\n",
        BareCRLF)
      _Case("bad_version",
        "GET / HTTP/5.6\r\nHost: a\r\n\r\n",
        InvalidVersion)
      _Case("non_token_method",
        "GE(T / HTTP/1.1\r\nHost: a\r\n\r\n",
        InvalidRequestLine)
      _Case("unknown_method",
        "FOOBAR / HTTP/1.1\r\nHost: a\r\n\r\n",
        UnknownMethod)
      _Case("multi_sp_request_line",
        "GET  / HTTP/1.1\r\nHost: a\r\n\r\n",
        InvalidRequestLine)
      _Case("space_in_request_target",
        "GET /a b HTTP/1.1\r\nHost: a\r\n\r\n",
        InvalidRequestLine)
      _Case("empty_request_target",
        "GET  HTTP/1.1\r\nHost: a\r\n\r\n",
        InvalidURI)
    ]

  fun header_validation(): Array[_Case] val =>
    """
    Header field-lines: name is `1*tchar` (`_Token`); value is free of CR/LF/NUL
    (CR/LF as `BareCRLF` via the line policy, NUL as `InvalidFieldValue`); no
    obs-fold; no whitespace before the colon.
    """
    [ _Case("ws_before_colon",
        "GET / HTTP/1.1\r\nHost: a\r\nFoo : bar\r\n\r\n",
        InvalidFieldName)
      _Case("non_token_field_name",
        "GET / HTTP/1.1\r\nHost: a\r\nFo@o: bar\r\n\r\n",
        InvalidFieldName)
      _Case("interior_ws_in_name",
        "POST / HTTP/1.1\r\nHost: a\r\nContent -Length: 5\r\n" +
        "Transfer-Encoding: chunked\r\n\r\n5\r\n01234\r\n0\r\n\r\n",
        InvalidFieldName)
      _Case("bare_cr_in_value",
        "GET / HTTP/1.1\r\nHost: a\r\nX: b\rc\r\n\r\n",
        BareCRLF)
      _Case("nul_in_value",
        "GET / HTTP/1.1\r\nHost: a\r\nX: b\x00c\r\n\r\n",
        InvalidFieldValue)
      _Case("obs_fold",
        "GET / HTTP/1.1\r\nHost: a\r\nX: b\r\n cont\r\n\r\n",
        ObsFold)
      _Case("leading_space_in_header_line",
        "GET / HTTP/1.1\r\n Host: a\r\n\r\n",
        ObsFold)
    ]

  fun content_length(): Array[_Case] val =>
    [ _Case("cl_simple_ok",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\n\r\nabc",
        _Accept("POST", "/", HTTP11, "abc"))
      _Case("cl_duplicate_disagree",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\n" +
        "Content-Length: 4\r\n\r\nabc",
        InvalidContentLength)
      _Case("cl_duplicate_same",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\n" +
        "Content-Length: 3\r\n\r\nabc",
        _Accept("POST", "/", HTTP11, "abc"))
      _Case("cl_comma_list_diff",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3, 4\r\n\r\nabc",
        InvalidContentLength)
      _Case("cl_comma_list_same",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3, 3\r\n\r\nabc",
        InvalidContentLength)
      _Case("cl_non_digit",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3abc\r\n\r\nabc",
        InvalidContentLength)
      _Case("cl_plus_prefix",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: +3\r\n\r\nabc",
        InvalidContentLength)
      _Case("cl_leading_zero",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 003\r\n\r\nabc",
        _Accept("POST", "/", HTTP11, "abc"))
      _Case("cl_empty",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: \r\n\r\nabc",
        InvalidContentLength)
    ]

  fun transfer_encoding(): Array[_Case] val =>
    [ _Case("chunked_ok",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\n\r\n",
        _Accept("POST", "/", HTTP11, "01234"))
      _Case("te_and_cl",
        "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n" +
        "Transfer-Encoding: chunked\r\n\r\n5\r\n01234\r\n0\r\n\r\n",
        ContentLengthWithTransferEncoding)
      _Case("te_cl_reordered",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n" +
        "Content-Length: 5\r\n\r\n5\r\n01234\r\n0\r\n\r\n",
        ContentLengthWithTransferEncoding)
      _Case("te_chunked_not_final",
        "POST / HTTP/1.1\r\nHost: a\r\n" +
        "Transfer-Encoding: chunked, gzip\r\n\r\n5\r\n01234\r\n0\r\n\r\n",
        InvalidTransferEncoding)
      _Case("te_double_chunked",
        "POST / HTTP/1.1\r\nHost: a\r\n" +
        "Transfer-Encoding: chunked, chunked\r\n\r\n5\r\n01234\r\n0\r\n\r\n",
        InvalidTransferEncoding)
      _Case("te_multi_header_chunked",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n" +
        "Transfer-Encoding: chunked\r\n\r\n5\r\n01234\r\n0\r\n\r\n",
        InvalidTransferEncoding)
      _Case("te_unknown_only",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: fugazi\r\n\r\n",
        UnsupportedTransferEncoding)
      _Case("te_obfuscated_control",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: \x0bchunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\n\r\n",
        InvalidTransferEncoding)
    ]

  fun chunked_body(): Array[_Case] val =>
    [ _Case("chunk_bare_lf_terminator",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\n01234\r\n0\r\n\r\n",
        BareCRLF)
      _Case("chunk_size_garbage_after",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5XX\r\n01234\r\n0\r\n\r\n",
        InvalidChunk)
      _Case("chunk_size_hex_prefix",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "0x5\r\n01234\r\n0\r\n\r\n",
        InvalidChunk)
      _Case("chunk_size_underscore",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5_0\r\n01234\r\n0\r\n\r\n",
        InvalidChunk)
      _Case("chunk_size_overflow_wraps_limit",
        // A first chunk advances total to 1, then a USize.max chunk-size would
        // wrap the body-size check below the limit with plain `+`. Must reject.
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "1\r\nX\r\nffffffffffffffff\r\n",
        BodyTooLarge)
      _Case("chunk_ext_nul",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;\x00\r\n01234\r\n0\r\n\r\n",
        InvalidChunkExtension)
      _Case("chunk_ext_bare_cr",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a\rb\r\n01234\r\n0\r\n\r\n",
        BareCRLF)
      _Case("chunk_ext_ok",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;ext\r\n01234\r\n0\r\n\r\n",
        _Accept("POST", "/", HTTP11, "01234"))
      _Case("chunk_ext_token_value",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a=b\r\n01234\r\n0\r\n\r\n",
        _Accept("POST", "/", HTTP11, "01234"))
      _Case("chunk_ext_quoted_value",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a=\"b\"\r\n01234\r\n0\r\n\r\n",
        _Accept("POST", "/", HTTP11, "01234"))
      _Case("chunk_ext_bad_name",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a@b\r\n01234\r\n0\r\n\r\n",
        InvalidChunkExtension)
      _Case("chunk_ext_empty_quoted_value",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a=\"\"\r\n01234\r\n0\r\n\r\n",
        _Accept("POST", "/", HTTP11, "01234"))
      _Case("chunk_ext_unterminated_quote",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a=\"b\r\n01234\r\n0\r\n\r\n",
        InvalidChunkExtension)
      _Case("chunk_ext_ctl_in_quoted",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5;a=\"\x01\"\r\n01234\r\n0\r\n\r\n",
        InvalidChunkExtension)
      _Case("chunk_data_bad_terminator",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234XY\r\n0\r\n\r\n",
        InvalidChunk)
      _Case("chunk_data_bare_lf_terminator",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\n0\r\n\r\n",
        InvalidChunk)
      _Case("chunk_missing_final_crlf",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\n",
        _Incomplete)
    ]

  fun trailers(): Array[_Case] val =>
    """
    Trailer field-lines pass through the SAME field-line gate as headers
    (`BareCRLF`, `InvalidFieldName`, `InvalidFieldValue`), plus the forbidden-
    trailer rule (RFC 9110 §6.5.1): framing/routing/control fields are rejected
    even when syntactically valid.
    """
    [ _Case("trailer_allowed_ok",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX-Checksum: abc\r\n\r\n",
        _Accept("POST", "/", HTTP11, "01234"))
      _Case("trailer_injection_te",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nTransfer-Encoding: chunked\r\n\r\n",
        ForbiddenTrailer)
      _Case("trailer_injection_cl",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nContent-Length: 5\r\n\r\n",
        ForbiddenTrailer)
      _Case("trailer_injection_host",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nHost: evil\r\n\r\n",
        ForbiddenTrailer)
      _Case("trailer_non_token_name",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nFo@o: bar\r\n\r\n",
        InvalidFieldName)
      _Case("trailer_bare_lf",
        "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n" +
        "5\r\n01234\r\n0\r\nX-Foo: a\nb\r\n\r\n",
        BareCRLF)
    ]
