use "uri"

class val Request
  """
  Immutable bundle of HTTP request metadata delivered to the server actor.

  Constructed by `HTTPServer` after parsing the request line, headers,
  and URI. Delivered to the actor via the
  `HTTPServerLifecycleEventReceiver.on_request()` callback, making it easy to
  pass request metadata to helper functions or store it for later use.

  All components are pre-validated before construction: the method is a known
  HTTP method, the URI is a parsed RFC 3986 structure, and the version is
  HTTP/1.0 or HTTP/1.1. Invalid requests are rejected with an error response
  before reaching the actor.
  """
  let method: Method
  let uri: URI val
  let version: Version
  let headers: Headers val

  new val create(
    method': Method,
    uri': URI val,
    version': Version,
    headers': Headers val)
  =>
    method = method'
    uri = uri'
    version = version'
    headers = headers'
