class val _AcceptRange
  """
  A single parsed media range from an Accept header.

  Stores the type/subtype, media parameters (excluding the quality factor),
  and the quality factor scaled to 0–1000.
  """
  let type_name: String val
  let subtype: String val
  let params: Array[(String val, String val)] val
  let quality: _Quality

  new val create(
    type_name': String val,
    subtype': String val,
    params': Array[(String val, String val)] val,
    quality': _Quality)
  =>
    type_name = type_name'
    subtype = subtype'
    params = params'
    quality = quality'

  fun _specificity(): USize =>
    """
    Return a specificity score for precedence ordering.

    0 = `*/*` (matches anything), 1 = `type/*` (matches any subtype),
    2 = `type/subtype` (exact match).
    """
    if type_name == "*" then
      0
    elseif subtype == "*" then
      1
    else
      2
    end
