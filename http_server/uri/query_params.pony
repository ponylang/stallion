class val QueryParams
  """
  Parsed query parameters with key-based lookup.

  Stores decoded key-value pairs in their original order. Duplicate keys
  are preserved — use `get()` for the first value or `get_all()` for every
  value associated with a key. Lookups are linear scans, which is
  appropriate for the small parameter counts typical of query strings.
  """
  let _pairs: Array[(String val, String val)] val

  new val create(p: Array[(String val, String val)] val) =>
    """Create from an array of decoded key-value pairs."""
    _pairs = p

  fun apply(i: USize): (String val, String val) ? =>
    """The pair at index `i`. Raises an error if out of bounds."""
    _pairs(i)?

  fun get(key: String): (String val | None) =>
    """
    First value for `key`, or `None` if the key is absent.

    When duplicate keys are possible and all values are needed, use
    `get_all()` instead.
    """
    for (k, v) in _pairs.values() do
      if k == key then return v end
    end
    None

  fun get_all(key: String): Array[String val] val =>
    """All values for `key`, in order. Empty array if absent."""
    let result = recover iso Array[String val] end
    for (k, v) in _pairs.values() do
      if k == key then result.push(v) end
    end
    consume result

  fun contains(key: String): Bool =>
    """Whether `key` is present."""
    for (k, _) in _pairs.values() do
      if k == key then return true end
    end
    false

  fun pairs(): ArrayValues[(String val, String val),
    Array[(String val, String val)] val]^
  =>
    """All pairs in their original order."""
    _pairs.values()

  fun size(): USize =>
    """Number of pairs, including duplicates."""
    _pairs.size()
