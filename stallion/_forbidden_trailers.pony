primitive _ForbiddenTrailers
  """
  RFC 9110 §6.5.1 — field names that must not appear in a trailer section.

  A trailer arrives after the body, so honoring a framing, routing, request-
  modifier, authentication, or payload-processing field there is a request-
  smuggling vector. This is the trailer analogue of `_ListValuedHeaders`: a
  curated denylist matched against the gate-normalized (lowercased) field name.
  Names not on the list are permitted as trailers — Stallion validates them but
  does not deliver them (the callback contract has no trailer event).
  """
  fun apply(name: String box): Bool =>
    """Whether `name` (lowercased) is forbidden in a trailer section."""
    match name
    // Message framing and routing.
    | "transfer-encoding" | "content-length" | "host"
    // Request modifiers / controls (RFC 9110 §6.5.1).
    | "cache-control" | "expect" | "max-forwards" | "pragma" | "range" | "te"
    // Authentication and credentials.
    | "authorization" | "proxy-authorization" | "cookie" | "set-cookie"
    // Payload processing.
    | "content-encoding" | "content-type" | "content-range" | "trailer" => true
    else
      false
    end
