class val MediaType is (Equatable[MediaType] & Stringable)
  """
  An HTTP media type consisting of a top-level type and subtype.

  Both components are lowercased at construction for case-insensitive
  comparison. No validation is performed on the values — this is consistent
  with `Header`, which stores names and values as-is.

  Use `ContentNegotiation` to match media types against an `Accept` header.
  """
  let type_name: String val
  let subtype: String val

  new val create(type_name': String val, subtype': String val) =>
    """Create a media type with the given type and subtype, lowercased."""
    type_name = type_name'.lower()
    subtype = subtype'.lower()

  fun eq(that: box->MediaType): Bool =>
    (type_name == that.type_name) and (subtype == that.subtype)

  fun ne(that: box->MediaType): Bool =>
    not eq(that)

  fun string(): String iso^ =>
    (type_name + "/" + subtype).clone()
