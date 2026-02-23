## Change start_chunked_response() to return StartChunkedResponseResult

`Responder.start_chunked_response()` now returns a `StartChunkedResponseResult` instead of nothing. The result indicates whether streaming was started (`StreamingStarted`), rejected because the request uses HTTP/1.0 (`ChunkedNotSupported`), or rejected because a response was already in progress (`AlreadyResponded`).

Previously, callers had no way to detect failure — the method silently no-oped. Now callers can match on the result and react appropriately, for example falling back to a complete response on HTTP/1.0.

Before:

```pony
responder.start_chunked_response(StatusOK, headers)
responder.send_chunk("data")
responder.finish_response()
// If HTTP/1.0, nothing happened — no way to know
responder.respond(fallback) // hope for the best
```

After:

```pony
match responder.start_chunked_response(StatusOK, headers)
| StreamingStarted =>
  responder.send_chunk("data")
  responder.finish_response()
| ChunkedNotSupported =>
  responder.respond(fallback)
| AlreadyResponded => None
end
```
