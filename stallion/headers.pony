class Headers
  """
  A collection of HTTP headers with case-insensitive name lookup.

  Names are lowercased on storage. Use `set()` to replace all values for a
  name, or `add()` to append an additional value (appropriate for multi-value
  headers like Set-Cookie).
  """
  embed _headers: Array[Header val]

  new create() =>
    """Create an empty header collection."""
    _headers = Array[Header val]

  fun ref set(name: String, value: String) =>
    """
    Set a header, removing any existing entries with the same name.

    After this call, `get(name)` returns `value` and there is exactly one
    entry for this name.
    """
    let lower_name: String val = name.lower()
    var i: USize = 0
    while i < _headers.size() do
      try
        if _headers(i)?.name == lower_name then
          _headers.delete(i)?
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    end
    _headers.push(Header(lower_name, value))

  fun ref add(name: String, value: String) =>
    """
    Add a header entry without removing existing entries with the same name.

    This is appropriate for headers that can appear multiple times
    (e.g., Set-Cookie). Use `set()` when you want to replace.
    """
    _headers.push(Header(name.lower(), value))

  fun ref _add_lowered(name: String val, value: String val) =>
    """
    Add a header entry whose name is ALREADY lowercased, skipping the redundant
    `lower()` that `add` performs.

    Precondition: `name` must already be lowercase — the parser's field-line
    gate normalizes it. Passing a mixed-case name here breaks case-insensitive
    `get()`/`set()` lookup, so external callers should use `add` instead.
    """
    _headers.push(Header(name, value))

  fun get(name: String): (String | None) =>
    """
    Get the value for the given header name (case-insensitive).

    A known set of comma-separated list fields — such as `Connection`,
    `Accept`, `Cache-Control`, and the other standard request list fields —
    are treated specially: the values of all lines with this name are
    combined into one value, joined by commas in the order they appeared, per
    RFC 9110 §5.3. For every other field, the first value is returned. A field
    not in the known set always returns its first value, so combine such a
    field's repeated lines yourself (via `values()`) if you need them.
    Returns `None` if no header with that name exists.

    The combined value is safe to split on commas for simple-token list
    fields like `Connection`. Complex list fields whose elements can contain
    quoted commas (e.g. `Accept`) need a quoted-string-aware tokenizer to
    split correctly — combining here does not change that.
    """
    let lower_name: String val = name.lower()
    if _ListValuedHeaders(lower_name) then
      let combined: String iso = recover iso String end
      var found = false
      for hdr in _headers.values() do
        if hdr.name == lower_name then
          if found then combined.append(",") end
          combined.append(hdr.value)
          found = true
        end
      end
      if found then consume combined else None end
    else
      for hdr in _headers.values() do
        if hdr.name == lower_name then return hdr.value end
      end
      None
    end

  fun size(): USize =>
    """Return the number of header entries."""
    _headers.size()

  fun values(): ArrayValues[Header val, this->Array[Header val]] =>
    """Iterate over all header entries as `Header val` objects."""
    _headers.values()
