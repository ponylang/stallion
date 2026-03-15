primitive ContentNegotiation
  """
  Select the best response content type based on the client's `Accept`
  header preferences (RFC 7231 §5.3.2).

  This is an opt-in utility — most endpoints serve a single content type, so
  automatic parsing of every request's Accept header would waste CPU. Call
  `from_request()` or `apply()` only in handlers that support multiple
  content types.

  Two entry points:

  * `from_request()` — extracts all `Accept` headers from a `Request val`
    and negotiates against the server's supported types.
  * `apply()` — negotiates directly from a raw Accept header value string.
    Useful for testing or when you already have the header value.

  The algorithm follows RFC 7231 §5.3.2 precedence rules:

  1. An absent Accept header means "accept anything" — the first supported
     type is returned.
  2. Each supported type is matched against the most specific compatible
     range in the Accept header. Ranges with media parameters only match
     types with matching parameters (but `MediaType` has no parameters, so
     parameterized ranges don't match).
  3. The supported type with the highest quality wins. Ties go to the first
     type in the `supported` list (server preference).
  4. Types matched only by `q=0` ranges are excluded.
  5. If no supported type has quality > 0, `NoAcceptableType` is returned.
  """

  fun from_request(
    request': Request val,
    supported: ReadSeq[MediaType val] box)
    : ContentNegotiationResult
  =>
    """
    Negotiate content type from a request's Accept headers.

    Multiple Accept headers are concatenated, matching RFC 7230 §3.2.2
    semantics for list-based header fields.
    """
    if supported.size() == 0 then
      return NoAcceptableType
    end

    // Collect all Accept header values
    var header_value: String val = ""
    var found: Bool = false
    for hdr in request'.headers.values() do
      if hdr.name == "accept" then
        if found then
          header_value = header_value + ", " + hdr.value
        else
          header_value = hdr.value
          found = true
        end
      end
    end

    if not found then
      // No Accept header — accept anything, return first supported
      try
        return supported(0)?
      else
        _Unreachable()
        return NoAcceptableType
      end
    end

    apply(header_value, supported)

  fun apply(
    header_value: String val,
    supported: ReadSeq[MediaType val] box)
    : ContentNegotiationResult
  =>
    """
    Negotiate content type from a raw Accept header value string.

    Empty `supported` always returns `NoAcceptableType`. An empty
    `header_value` means "accept anything" — the first supported type
    is returned.
    """
    if supported.size() == 0 then
      return NoAcceptableType
    end

    let ranges = _AcceptParser(header_value)

    // Empty ranges (empty Accept value) — accept anything
    if ranges.size() == 0 then
      try
        return supported(0)?
      else
        _Unreachable()
        return NoAcceptableType
      end
    end

    // For each supported type, find the best matching range
    var best_type: (MediaType val | None) = None
    var best_quality: U16 = 0

    try
      var i: USize = 0
      while i < supported.size() do
        let media_type = supported(i)?
        let q = _best_quality_for(media_type, ranges)

        if q > best_quality then
          best_quality = q
          best_type = media_type
        end
        i = i + 1
      end
    else
      _Unreachable()
    end

    if best_quality > 0 then
      match best_type
      | let mt: MediaType val => mt
      else
        NoAcceptableType
      end
    else
      NoAcceptableType
    end

  fun _best_quality_for(
    media_type: MediaType val,
    ranges: Array[_AcceptRange val] val)
    : U16
  =>
    """
    Find the quality of the most specific matching range for a media type.

    Returns 0 if no range matches or the best match has q=0.
    """
    var best_specificity: USize = 0
    var best_quality: U16 = 0
    var found: Bool = false

    for range in ranges.values() do
      if not _range_matches(media_type, range) then
        continue
      end

      let specificity = range._specificity()

      if (not found) or (specificity > best_specificity) then
        best_specificity = specificity
        best_quality = range.quality()
        found = true
      end
    end

    if found then best_quality else 0 end

  fun _range_matches(
    media_type: MediaType val,
    range: _AcceptRange val)
    : Bool
  =>
    """
    Check whether a media type matches an Accept range.

    Ranges with media parameters (excluding q) don't match parameterless
    `MediaType` values, since `MediaType` carries no parameters.
    """
    // Parameterized ranges don't match our parameterless MediaType
    if range.params.size() > 0 then
      return false
    end

    if range.type_name == "*" then
      // */* matches everything
      true
    elseif range.subtype == "*" then
      // type/* matches if type matches
      media_type.type_name == range.type_name
    else
      // Exact match
      (media_type.type_name == range.type_name) and
        (media_type.subtype == range.subtype)
    end
