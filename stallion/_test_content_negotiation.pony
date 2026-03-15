use "pony_check"
use "pony_test"
use uri_pkg = "uri"

// --- Property-based tests ---

class \nodoc\ iso _PropertyNegotiateRobustness
  is Property1[String val]
  """Arbitrary strings never crash the parser or negotiation."""
  fun name(): String => "content_negotiation/robustness"

  fun gen(): Generator[String val] =>
    Generators.ascii_printable(0, 200)

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    // Must not crash — result is always one of the two valid variants
    match ContentNegotiation(arg1, supported)
    | let mt: MediaType val =>
      ph.assert_true(
        (mt == MediaType("text", "html")) or
          (mt == MediaType("application", "json")),
        "Result must be from supported list")
    | NoAcceptableType => None
    end

class \nodoc\ iso _PropertyNegotiateResultFromSupported
  is Property1[USize]
  """
  Negotiation result is always from the supported list or NoAcceptableType.
  """
  fun name(): String => "content_negotiation/result_from_supported"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 4)

  fun ref property(arg1: USize, ph: PropertyHelper) =>
    let all_types: Array[MediaType val] val = [as MediaType val:
      MediaType("text", "html")
      MediaType("text", "plain")
      MediaType("application", "json")
      MediaType("application", "xml")
      MediaType("image", "png")
    ]
    // Build supported list of size arg1
    let supported = recover val
      let arr = Array[MediaType val]
      var i: USize = 0
      while i < arg1.min(all_types.size()) do
        try arr.push(all_types(i)?) end
        i = i + 1
      end
      arr
    end

    let result = ContentNegotiation(
      "text/html, application/json;q=0.9, */*;q=0.1", supported)

    match result
    | let mt: MediaType val =>
      var found = false
      for s in supported.values() do
        if s == mt then found = true; break end
      end
      ph.assert_true(found, "Result must be in supported list")
    | NoAcceptableType =>
      if supported.size() > 0 then
        // */* should match anything, so this shouldn't happen
        ph.fail("Expected a match with */* in accept header")
      end
    end

class \nodoc\ iso _PropertyNegotiateQZeroExcludes
  is Property1[USize]
  """Types explicitly excluded with q=0 are never returned."""
  fun name(): String => "content_negotiation/q_zero_excludes"

  fun gen(): Generator[USize] =>
    Generators.usize(0, 2)

  fun ref property(arg1: USize, ph: PropertyHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
      MediaType("text", "plain")
    ]
    // Exclude the type at index arg1
    let excluded = try supported(arg1)? else return end
    let accept = excluded.string() + ";q=0, */*;q=0.1"
    let result = ContentNegotiation(consume accept, supported)

    match result
    | let mt: MediaType val =>
      ph.assert_false(mt == excluded,
        "Excluded type " + excluded.string() + " should not be returned")
    | NoAcceptableType => None
    end

class \nodoc\ iso _PropertyNegotiateServerPreference
  is Property1[USize]
  """Equal quality returns the first type in the supported list."""
  fun name(): String => "content_negotiation/server_preference"

  fun gen(): Generator[USize] =>
    Generators.usize(2, 5)

  fun ref property(arg1: USize, ph: PropertyHelper) =>
    // Build a supported list of text/typeN
    let supported = recover val
      let arr = Array[MediaType val]
      var i: USize = 0
      while i < arg1 do
        arr.push(MediaType("text", "type" + i.string()))
        i = i + 1
      end
      arr
    end

    // Accept */* with default quality — all equal
    let result = ContentNegotiation("*/*", supported)

    match result
    | let mt: MediaType val =>
      try
        ph.assert_true(mt == supported(0)?,
          "Expected first supported type, got " + mt.string())
      else
        ph.fail("server preference: index error")
      end
    | NoAcceptableType =>
      if supported.size() > 0 then
        ph.fail("Expected a match with */*")
      end
    end

class \nodoc\ iso _PropertyNegotiateQualityBounds
  is Property1[String val]
  """All parsed qualities fall in the 0–1000 range."""
  fun name(): String => "content_negotiation/quality_bounds"

  fun gen(): Generator[String val] =>
    Generators.ascii_printable(0, 100)

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    // Indirectly verify via the constrained type — if parsing produces
    // a result, the quality was valid. This test ensures the parser
    // never constructs an _AcceptRange with an out-of-range quality.
    let ranges = _AcceptParser(arg1)
    for range in ranges.values() do
      ph.assert_true(range.quality() <= 1000,
        "Quality out of range: " + range.quality().string())
    end

// --- Example-based tests ---

class \nodoc\ iso _TestNegotiateKnownGood is UnitTest
  """Verify negotiation for specific Accept headers."""
  fun name(): String => "content_negotiation/known_good"

  fun apply(h: TestHelper) =>
    _test_exact_match(h)
    _test_quality_ordering(h)
    _test_wildcard_match(h)
    _test_type_wildcard(h)
    _test_q_zero_exclusion(h)
    _test_specificity_precedence(h)
    _test_missing_accept(h)
    _test_empty_supported(h)
    _test_server_preference_tiebreak(h)
    _test_case_insensitivity(h)
    _test_browser_accept(h)
    _test_multiple_accept_headers(h)
    _test_empty_accept_value(h)
    _test_all_excluded(h)
    _test_whitespace_tolerance(h)
    _test_malformed_entries_skipped(h)
    _test_quality_edge_values(h)
    _test_bare_dot_quality_not_excluded(h)
    _test_quoted_string_comma_protection(h)
    _test_parameterized_range_no_match(h)
    _test_accept_extensions_ignored(h)
    _test_wildcard_subtype_only_rejected(h)
    _test_specificity_overrides_wildcard_q_zero(h)
    _test_type_wildcard_vs_exact_specificity(h)
    _test_type_wildcard_q_zero_exclusion(h)

  fun _test_exact_match(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    match ContentNegotiation("application/json", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "exact match")
    | NoAcceptableType =>
      h.fail("exact match: expected json")
    end

  fun _test_quality_ordering(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    match ContentNegotiation("text/html;q=0.5, application/json;q=0.9",
      supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "quality ordering: expected json")
    | NoAcceptableType =>
      h.fail("quality ordering: expected match")
    end

  fun _test_wildcard_match(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("application", "json")
    ]
    match ContentNegotiation("*/*", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "wildcard match")
    | NoAcceptableType =>
      h.fail("wildcard match: expected json")
    end

  fun _test_type_wildcard(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "plain")
      MediaType("application", "json")
    ]
    match ContentNegotiation("application/*", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "type wildcard")
    | NoAcceptableType =>
      h.fail("type wildcard: expected json")
    end

  fun _test_q_zero_exclusion(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    match ContentNegotiation(
      "text/html;q=0, application/json", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "q=0 exclusion")
    | NoAcceptableType =>
      h.fail("q=0 exclusion: expected json")
    end

  fun _test_specificity_precedence(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("text", "plain")
    ]
    // */* at q=0.1, but text/html specifically at q=0.9
    match ContentNegotiation(
      "*/*;q=0.1, text/html;q=0.9", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "specificity precedence: expected html")
    | NoAcceptableType =>
      h.fail("specificity precedence: expected match")
    end

  fun _test_missing_accept(h: TestHelper) =>
    // from_request with no Accept header — should return first supported
    let headers = recover val Headers end
    let request' = _make_request(headers)
    let supported = [as MediaType val:
      MediaType("application", "json")
      MediaType("text", "html")
    ]
    match ContentNegotiation.from_request(request', supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "missing accept: expected first supported")
    | NoAcceptableType =>
      h.fail("missing accept: expected match")
    end

  fun _test_empty_supported(h: TestHelper) =>
    match ContentNegotiation("text/html", Array[MediaType val])
    | NoAcceptableType => None
    | let mt: MediaType val =>
      h.fail("empty supported: expected NoAcceptableType")
    end

  fun _test_server_preference_tiebreak(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "plain")
      MediaType("application", "json")
    ]
    // Both at same quality
    match ContentNegotiation(
      "text/plain, application/json", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "plain"),
        "tiebreak: expected first supported (text/plain)")
    | NoAcceptableType =>
      h.fail("tiebreak: expected match")
    end

  fun _test_case_insensitivity(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("Application", "JSON")
    ]
    match ContentNegotiation("APPLICATION/json", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "case insensitivity")
    | NoAcceptableType =>
      h.fail("case insensitivity: expected match")
    end

  fun _test_browser_accept(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    // Typical browser Accept header
    let accept =
      "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    match ContentNegotiation(accept, supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "browser accept: expected html")
    | NoAcceptableType =>
      h.fail("browser accept: expected match")
    end

  fun _test_multiple_accept_headers(h: TestHelper) =>
    // Multiple Accept headers should be concatenated
    let headers = recover val
      let h' = Headers
      h'.add("accept", "text/plain;q=0.5")
      h'.add("accept", "application/json")
      h'.add("content-type", "text/html")
      h'
    end
    let request' = _make_request(headers)
    let supported = [as MediaType val:
      MediaType("text", "plain")
      MediaType("application", "json")
    ]
    match ContentNegotiation.from_request(request', supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "multiple accept: expected json (higher quality)")
    | NoAcceptableType =>
      h.fail("multiple accept: expected match")
    end

  fun _test_empty_accept_value(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
    ]
    // Empty Accept value — accept anything
    match ContentNegotiation("", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "empty accept value: expected first supported")
    | NoAcceptableType =>
      h.fail("empty accept value: expected match")
    end

  fun _test_all_excluded(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    match ContentNegotiation(
      "text/html;q=0, application/json;q=0", supported)
    | NoAcceptableType => None
    | let mt: MediaType val =>
      h.fail("all excluded: expected NoAcceptableType, got " + mt.string())
    end

  fun _test_whitespace_tolerance(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    match ContentNegotiation(
      "  text/html  ;  q=0.5  ,  application/json  ", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "whitespace tolerance: expected json (higher quality)")
    | NoAcceptableType =>
      h.fail("whitespace tolerance: expected match")
    end

  fun _test_malformed_entries_skipped(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
    ]
    // "badentry" has no slash — should be skipped; text/html should match
    match ContentNegotiation("badentry, text/html", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "malformed skipped: expected html")
    | NoAcceptableType =>
      h.fail("malformed skipped: expected match")
    end

  fun _test_quality_edge_values(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "a")
      MediaType("text", "b")
      MediaType("text", "c")
    ]
    // q=0.001 (minimum positive), q=0.999, q=1.000
    match ContentNegotiation(
      "text/a;q=0.001, text/b;q=0.999, text/c;q=1.000", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "c"),
        "quality edge: expected c (q=1.000)")
    | NoAcceptableType =>
      h.fail("quality edge: expected match")
    end

  fun _test_bare_dot_quality_not_excluded(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
    ]
    // "q=." is malformed — bare dot with no digits. Must not be treated
    // as q=0 (which would exclude the type). Malformed quality defaults
    // to 1.0.
    match ContentNegotiation("text/html;q=.", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "bare dot quality: expected match (malformed q defaults to 1.0)")
    | NoAcceptableType =>
      h.fail("bare dot quality: q=. must not exclude")
    end

  fun _test_quoted_string_comma_protection(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
    ]
    // Comma inside a quoted accept-extension value should not split.
    // The extension param appears after q, so it's discarded for matching
    // but must not cause a spurious comma split.
    match ContentNegotiation(
      "text/html;q=0.5;ext=\"a,b\"", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "quoted comma protection")
    | NoAcceptableType =>
      h.fail("quoted comma protection: expected match")
    end

  fun _test_parameterized_range_no_match(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
    ]
    // Range with media params doesn't match parameterless MediaType
    match ContentNegotiation("text/html;level=1", supported)
    | NoAcceptableType => None
    | let mt: MediaType val =>
      h.fail("parameterized range: expected NoAcceptableType")
    end

  fun _test_accept_extensions_ignored(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
    ]
    // Extensions after q are not media parameters — they must not
    // prevent matching (RFC 7231 §5.3.2).
    match ContentNegotiation("text/html;q=0.9;level=1", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "accept extensions: expected match")
    | NoAcceptableType =>
      h.fail("accept extensions: extension after q should not block match")
    end

  fun _test_wildcard_subtype_only_rejected(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("text", "plain")
    ]
    // */html is not valid per RFC 7231 — only */* is a valid wildcard.
    // Parser skips it as malformed. When combined with valid ranges,
    // */html must not act as a wildcard match.
    match ContentNegotiation("*/html;q=0.9, text/plain;q=0.5", supported)
    | let mt: MediaType val =>
      // If */html were treated as */* (the bug), text/html would match
      // at q=0.9. With the fix, only text/plain matches at q=0.5.
      h.assert_true(mt == MediaType("text", "plain"),
        "wildcard subtype: */html rejected, expected plain")
    | NoAcceptableType =>
      h.fail("wildcard subtype: expected plain to match")
    end

  fun _test_specificity_overrides_wildcard_q_zero(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    // */* at q=0 excludes everything, but the exact text/html range
    // at q=0.9 is more specific and overrides the wildcard exclusion.
    // application/json has no specific range, so it stays excluded.
    match ContentNegotiation(
      "*/*;q=0, text/html;q=0.9", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "html"),
        "specificity overrides wildcard q=0: expected html")
    | NoAcceptableType =>
      h.fail("specificity overrides wildcard q=0: expected match")
    end

  fun _test_type_wildcard_vs_exact_specificity(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("text", "plain")
    ]
    // text/* at q=0.9 matches both, but text/html has a more specific
    // exact range at q=0.5. The exact match wins for text/html (q=0.5),
    // while text/plain uses the wildcard (q=0.9). So text/plain wins.
    match ContentNegotiation(
      "text/*;q=0.9, text/html;q=0.5", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "plain"),
        "type wildcard vs exact: expected plain (q=0.9 > q=0.5)")
    | NoAcceptableType =>
      h.fail("type wildcard vs exact: expected match")
    end

  fun _test_type_wildcard_q_zero_exclusion(h: TestHelper) =>
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("application", "json")
    ]
    // text/* at q=0 excludes all text/* types.
    // application/json has an exact match at default quality.
    match ContentNegotiation(
      "text/*;q=0, application/json", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("application", "json"),
        "type wildcard q=0: expected json")
    | NoAcceptableType =>
      h.fail("type wildcard q=0: expected match")
    end

  fun _make_request(headers: Headers val): Request val =>
    """Build a minimal Request for testing."""
    let parsed_uri: uri_pkg.URI val =
      match uri_pkg.ParseURI("/")
      | let u: uri_pkg.URI val => u
      | let _: uri_pkg.URIParseError val =>
        // "/" always parses — use a fallback to satisfy the compiler
        uri_pkg.URI(None, None, "/", None, None)
      end
    Request(GET, parsed_uri, HTTP11, headers,
      ParseCookies.from_headers(headers))

class \nodoc\ iso _TestAcceptParserKnownGood is UnitTest
  """Verify parsing of specific Accept header strings."""
  fun name(): String => "content_negotiation/parser_known_good"

  fun apply(h: TestHelper) =>
    _test_single_type(h)
    _test_multiple_types(h)
    _test_quality_values(h)
    _test_wildcards(h)
    _test_whitespace(h)
    _test_malformed_skipped(h)
    _test_empty_string(h)
    _test_quoted_comma_not_split(h)
    _test_wildcard_subtype_only_skipped(h)
    _test_accept_extension_not_in_params(h)
    _test_duplicate_range_first_wins(h)

  fun _test_single_type(h: TestHelper) =>
    let ranges = _AcceptParser("text/html")
    h.assert_eq[USize](1, ranges.size(), "single: count")
    try
      h.assert_eq[String val]("text", ranges(0)?.type_name,
        "single: type")
      h.assert_eq[String val]("html", ranges(0)?.subtype,
        "single: subtype")
      h.assert_eq[U16](1000, ranges(0)?.quality(),
        "single: quality")
    else
      h.fail("single: index error")
    end

  fun _test_multiple_types(h: TestHelper) =>
    let ranges = _AcceptParser("text/html, application/json, text/plain")
    h.assert_eq[USize](3, ranges.size(), "multiple: count")
    try
      h.assert_eq[String val]("text", ranges(0)?.type_name,
        "multiple: 0 type")
      h.assert_eq[String val]("html", ranges(0)?.subtype,
        "multiple: 0 subtype")
      h.assert_eq[String val]("application", ranges(1)?.type_name,
        "multiple: 1 type")
      h.assert_eq[String val]("json", ranges(1)?.subtype,
        "multiple: 1 subtype")
      h.assert_eq[String val]("text", ranges(2)?.type_name,
        "multiple: 2 type")
      h.assert_eq[String val]("plain", ranges(2)?.subtype,
        "multiple: 2 subtype")
    else
      h.fail("multiple: index error")
    end

  fun _test_quality_values(h: TestHelper) =>
    let ranges = _AcceptParser(
      "text/html;q=0.9, application/json;q=0.5, text/*;q=0.1")
    h.assert_eq[USize](3, ranges.size(), "quality: count")
    try
      h.assert_eq[U16](900, ranges(0)?.quality(), "quality: html")
      h.assert_eq[U16](500, ranges(1)?.quality(), "quality: json")
      h.assert_eq[U16](100, ranges(2)?.quality(), "quality: text/*")
    else
      h.fail("quality: index error")
    end

  fun _test_wildcards(h: TestHelper) =>
    let ranges = _AcceptParser("*/*;q=0.1, text/*;q=0.5")
    h.assert_eq[USize](2, ranges.size(), "wildcards: count")
    try
      h.assert_eq[String val]("*", ranges(0)?.type_name,
        "wildcards: 0 type")
      h.assert_eq[String val]("*", ranges(0)?.subtype,
        "wildcards: 0 subtype")
      h.assert_eq[String val]("text", ranges(1)?.type_name,
        "wildcards: 1 type")
      h.assert_eq[String val]("*", ranges(1)?.subtype,
        "wildcards: 1 subtype")
    else
      h.fail("wildcards: index error")
    end

  fun _test_whitespace(h: TestHelper) =>
    let ranges = _AcceptParser(
      "  text/html  ;  q=0.9  ,  application/json  ")
    h.assert_eq[USize](2, ranges.size(), "whitespace: count")
    try
      h.assert_eq[String val]("text", ranges(0)?.type_name,
        "whitespace: 0 type")
      h.assert_eq[U16](900, ranges(0)?.quality(),
        "whitespace: 0 quality")
      h.assert_eq[String val]("application", ranges(1)?.type_name,
        "whitespace: 1 type")
      h.assert_eq[U16](1000, ranges(1)?.quality(),
        "whitespace: 1 quality")
    else
      h.fail("whitespace: index error")
    end

  fun _test_malformed_skipped(h: TestHelper) =>
    let ranges = _AcceptParser("badentry, /bad, text/html, /")
    h.assert_eq[USize](1, ranges.size(), "malformed: count")
    try
      h.assert_eq[String val]("text", ranges(0)?.type_name,
        "malformed: type")
    else
      h.fail("malformed: index error")
    end

  fun _test_empty_string(h: TestHelper) =>
    let ranges = _AcceptParser("")
    h.assert_eq[USize](0, ranges.size(), "empty: count")

  fun _test_quoted_comma_not_split(h: TestHelper) =>
    // Comma inside a quoted parameter value must not split entries.
    // Without quote awareness, "a,b" would split into two entries.
    let ranges = _AcceptParser(
      "text/html;param=\"a,b\", application/json")
    h.assert_eq[USize](2, ranges.size(), "quoted comma: count")
    try
      h.assert_eq[String val]("text", ranges(0)?.type_name,
        "quoted comma: 0 type")
      h.assert_eq[String val]("html", ranges(0)?.subtype,
        "quoted comma: 0 subtype")
      h.assert_eq[String val]("application", ranges(1)?.type_name,
        "quoted comma: 1 type")
      h.assert_eq[String val]("json", ranges(1)?.subtype,
        "quoted comma: 1 subtype")
    else
      h.fail("quoted comma: index error")
    end

  fun _test_wildcard_subtype_only_skipped(h: TestHelper) =>
    // */html is malformed — only */* is valid. Parser should skip it.
    let ranges = _AcceptParser("*/html, text/plain")
    h.assert_eq[USize](1, ranges.size(), "*/html skipped: count")
    try
      h.assert_eq[String val]("text", ranges(0)?.type_name,
        "*/html skipped: type")
      h.assert_eq[String val]("plain", ranges(0)?.subtype,
        "*/html skipped: subtype")
    else
      h.fail("*/html skipped: index error")
    end

  fun _test_accept_extension_not_in_params(h: TestHelper) =>
    // Parameters after q are accept extensions, not media parameters.
    // They should not appear in the range's params array.
    let ranges = _AcceptParser("text/html;level=1;q=0.9;ext=2")
    h.assert_eq[USize](1, ranges.size(), "extension params: count")
    try
      // level=1 is before q — it's a media parameter
      h.assert_eq[USize](1, ranges(0)?.params.size(),
        "extension params: only media param, not extension")
      h.assert_eq[String val]("level",
        ranges(0)?.params(0)?._1, "extension params: param name")
      h.assert_eq[U16](900, ranges(0)?.quality(),
        "extension params: quality")
    else
      h.fail("extension params: index error")
    end

  fun _test_duplicate_range_first_wins(h: TestHelper) =>
    // When the same type appears twice with different qualities,
    // the first occurrence wins (equal specificity, first in header order).
    let ranges = _AcceptParser("text/html;q=0.5, text/html;q=0.9")
    h.assert_eq[USize](2, ranges.size(), "duplicate: count")
    // Both parse correctly
    try
      h.assert_eq[U16](500, ranges(0)?.quality(), "duplicate: first q")
      h.assert_eq[U16](900, ranges(1)?.quality(), "duplicate: second q")
    else
      h.fail("duplicate: index error")
    end
    // Negotiation uses the first matching range for text/html (q=0.5).
    // text/plain at q=0.7 should win because 0.7 > 0.5.
    // If the code incorrectly used the second range (q=0.9), text/html
    // would win instead.
    let supported = [as MediaType val:
      MediaType("text", "html")
      MediaType("text", "plain")
    ]
    match ContentNegotiation(
      "text/html;q=0.5, text/html;q=0.9, text/plain;q=0.7", supported)
    | let mt: MediaType val =>
      h.assert_true(mt == MediaType("text", "plain"),
        "duplicate: expected plain (q=0.7 > first html q=0.5)")
    | NoAcceptableType =>
      h.fail("duplicate: expected match")
    end
