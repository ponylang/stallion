interface val Status is Stringable
  """An HTTP response status code with numeric code and reason phrase."""
  fun code(): U16
  fun reason(): String val

// --- 1xx Informational ---

primitive StatusContinue is Status
  """100 Continue."""
  fun code(): U16 => 100
  fun reason(): String val => "Continue"
  fun string(): String iso^ => "100 Continue".clone()

primitive StatusSwitchingProtocols is Status
  """101 Switching Protocols."""
  fun code(): U16 => 101
  fun reason(): String val => "Switching Protocols"
  fun string(): String iso^ => "101 Switching Protocols".clone()

// --- 2xx Success ---

primitive StatusOK is Status
  """200 OK."""
  fun code(): U16 => 200
  fun reason(): String val => "OK"
  fun string(): String iso^ => "200 OK".clone()

primitive StatusCreated is Status
  """201 Created."""
  fun code(): U16 => 201
  fun reason(): String val => "Created"
  fun string(): String iso^ => "201 Created".clone()

primitive StatusAccepted is Status
  """202 Accepted."""
  fun code(): U16 => 202
  fun reason(): String val => "Accepted"
  fun string(): String iso^ => "202 Accepted".clone()

primitive StatusNoContent is Status
  """204 No Content."""
  fun code(): U16 => 204
  fun reason(): String val => "No Content"
  fun string(): String iso^ => "204 No Content".clone()

primitive StatusPartialContent is Status
  """206 Partial Content."""
  fun code(): U16 => 206
  fun reason(): String val => "Partial Content"
  fun string(): String iso^ => "206 Partial Content".clone()

// --- 3xx Redirection ---

primitive StatusMovedPermanently is Status
  """301 Moved Permanently."""
  fun code(): U16 => 301
  fun reason(): String val => "Moved Permanently"
  fun string(): String iso^ => "301 Moved Permanently".clone()

primitive StatusFound is Status
  """302 Found."""
  fun code(): U16 => 302
  fun reason(): String val => "Found"
  fun string(): String iso^ => "302 Found".clone()

primitive StatusSeeOther is Status
  """303 See Other."""
  fun code(): U16 => 303
  fun reason(): String val => "See Other"
  fun string(): String iso^ => "303 See Other".clone()

primitive StatusNotModified is Status
  """304 Not Modified."""
  fun code(): U16 => 304
  fun reason(): String val => "Not Modified"
  fun string(): String iso^ => "304 Not Modified".clone()

primitive StatusTemporaryRedirect is Status
  """307 Temporary Redirect."""
  fun code(): U16 => 307
  fun reason(): String val => "Temporary Redirect"
  fun string(): String iso^ => "307 Temporary Redirect".clone()

primitive StatusPermanentRedirect is Status
  """308 Permanent Redirect."""
  fun code(): U16 => 308
  fun reason(): String val => "Permanent Redirect"
  fun string(): String iso^ => "308 Permanent Redirect".clone()

// --- 4xx Client Error ---

primitive StatusBadRequest is Status
  """400 Bad Request."""
  fun code(): U16 => 400
  fun reason(): String val => "Bad Request"
  fun string(): String iso^ => "400 Bad Request".clone()

primitive StatusUnauthorized is Status
  """401 Unauthorized."""
  fun code(): U16 => 401
  fun reason(): String val => "Unauthorized"
  fun string(): String iso^ => "401 Unauthorized".clone()

primitive StatusForbidden is Status
  """403 Forbidden."""
  fun code(): U16 => 403
  fun reason(): String val => "Forbidden"
  fun string(): String iso^ => "403 Forbidden".clone()

primitive StatusNotFound is Status
  """404 Not Found."""
  fun code(): U16 => 404
  fun reason(): String val => "Not Found"
  fun string(): String iso^ => "404 Not Found".clone()

primitive StatusMethodNotAllowed is Status
  """405 Method Not Allowed."""
  fun code(): U16 => 405
  fun reason(): String val => "Method Not Allowed"
  fun string(): String iso^ => "405 Method Not Allowed".clone()

primitive StatusNotAcceptable is Status
  """406 Not Acceptable."""
  fun code(): U16 => 406
  fun reason(): String val => "Not Acceptable"
  fun string(): String iso^ => "406 Not Acceptable".clone()

primitive StatusRequestTimeout is Status
  """408 Request Timeout."""
  fun code(): U16 => 408
  fun reason(): String val => "Request Timeout"
  fun string(): String iso^ => "408 Request Timeout".clone()

primitive StatusConflict is Status
  """409 Conflict."""
  fun code(): U16 => 409
  fun reason(): String val => "Conflict"
  fun string(): String iso^ => "409 Conflict".clone()

primitive StatusGone is Status
  """410 Gone."""
  fun code(): U16 => 410
  fun reason(): String val => "Gone"
  fun string(): String iso^ => "410 Gone".clone()

primitive StatusLengthRequired is Status
  """411 Length Required."""
  fun code(): U16 => 411
  fun reason(): String val => "Length Required"
  fun string(): String iso^ => "411 Length Required".clone()

primitive StatusPayloadTooLarge is Status
  """413 Payload Too Large."""
  fun code(): U16 => 413
  fun reason(): String val => "Payload Too Large"
  fun string(): String iso^ => "413 Payload Too Large".clone()

primitive StatusURITooLong is Status
  """414 URI Too Long."""
  fun code(): U16 => 414
  fun reason(): String val => "URI Too Long"
  fun string(): String iso^ => "414 URI Too Long".clone()

primitive StatusUnsupportedMediaType is Status
  """415 Unsupported Media Type."""
  fun code(): U16 => 415
  fun reason(): String val => "Unsupported Media Type"
  fun string(): String iso^ => "415 Unsupported Media Type".clone()

primitive StatusUnprocessableEntity is Status
  """422 Unprocessable Entity."""
  fun code(): U16 => 422
  fun reason(): String val => "Unprocessable Entity"
  fun string(): String iso^ => "422 Unprocessable Entity".clone()

primitive StatusTooManyRequests is Status
  """429 Too Many Requests."""
  fun code(): U16 => 429
  fun reason(): String val => "Too Many Requests"
  fun string(): String iso^ => "429 Too Many Requests".clone()

primitive StatusRequestHeaderFieldsTooLarge is Status
  """431 Request Header Fields Too Large."""
  fun code(): U16 => 431
  fun reason(): String val => "Request Header Fields Too Large"
  fun string(): String iso^ => "431 Request Header Fields Too Large".clone()

// --- 5xx Server Error ---

primitive StatusInternalServerError is Status
  """500 Internal Server Error."""
  fun code(): U16 => 500
  fun reason(): String val => "Internal Server Error"
  fun string(): String iso^ => "500 Internal Server Error".clone()

primitive StatusNotImplemented is Status
  """501 Not Implemented."""
  fun code(): U16 => 501
  fun reason(): String val => "Not Implemented"
  fun string(): String iso^ => "501 Not Implemented".clone()

primitive StatusBadGateway is Status
  """502 Bad Gateway."""
  fun code(): U16 => 502
  fun reason(): String val => "Bad Gateway"
  fun string(): String iso^ => "502 Bad Gateway".clone()

primitive StatusServiceUnavailable is Status
  """503 Service Unavailable."""
  fun code(): U16 => 503
  fun reason(): String val => "Service Unavailable"
  fun string(): String iso^ => "503 Service Unavailable".clone()

primitive StatusGatewayTimeout is Status
  """504 Gateway Timeout."""
  fun code(): U16 => 504
  fun reason(): String val => "Gateway Timeout"
  fun string(): String iso^ => "504 Gateway Timeout".clone()

primitive StatusHTTPVersionNotSupported is Status
  """505 HTTP Version Not Supported."""
  fun code(): U16 => 505
  fun reason(): String val => "HTTP Version Not Supported"
  fun string(): String iso^ => "505 HTTP Version Not Supported".clone()
