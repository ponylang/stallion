## Fix a hang when closing a connection from a request callback

Calling `HTTPServer.close()` from inside `on_request()`, `on_body_chunk()`, or `on_request_complete()` — rejecting an oversized request with a 413 as soon as the headers arrive, for example — could leave the connection attempting one more read on the socket it had just closed. Under connection churn, with many connections opening and closing, that stray read could block one of the runtime's scheduler threads and keep the program from exiting.

Closing a connection from a request callback no longer leaves that read outstanding.

## Fix a connection wedging under sustained write backpressure

A connection could permanently stop making progress under sustained write backpressure while the client was still sending. Stallion stops reading from a connection while backpressure is applied to it, and under sustained backpressure that pause could become permanent: data stopped moving in both directions and the connection did not recover on its own, staying wedged until something closed it. It was most likely to appear on a multi-threaded runtime.

Such a connection now recovers and continues once the backpressure clears.

## Fix backpressure not stopping incoming requests on an HTTPS connection

When the send buffer fills, stallion stops reading from the connection and `on_throttled()` fires. On an HTTPS connection reading continued anyway: everything already decrypted from the same read was parsed, so an actor that had just received `on_throttled()` was handed more requests through `on_request()`, `on_body_chunk()`, and `on_request_complete()`. Stallion supports HTTP pipelining, so one read can carry several requests.

Reading now stops on an HTTPS connection as soon as backpressure is applied, the same as on a plaintext one. Data already decrypted is held rather than dropped. It is parsed once backpressure clears and `on_unthrottled()` fires, ahead of anything read off the socket afterward.

## Fix on_chunk_sent firing once per write-queue drain instead of once per chunk

`Responder.send_chunk()` returns a `ChunkSendToken`, and `on_chunk_sent()` fires with that token only after the chunk's bytes have reached the operating system. That pairing is what flow-controlled streaming is built on: send a chunk, wait for its callback, send the next. It did not hold. One callback was delivered each time the write queue drained completely rather than one per chunk, so an actor that sent several chunks while the socket was backed up got fewer callbacks than it had chunks outstanding.

An actor that drives the next chunk from `on_chunk_sent()`, which is what `examples/streaming` does, stops sending when a callback it is waiting on never arrives, and the response is never finished. Keeping more than one chunk in flight made this more likely, because that is exactly when several chunks drain together.

Your actor no longer gets one callback per write-queue drain. Each callback carries the token of a single chunk, and the callbacks arrive in the order the chunks were sent.

## Fix on_chunk_sent not firing when the connection closes

A chunk whose bytes had reached the operating system got no `on_chunk_sent()` callback at all if the connection then closed. The callback was discarded the moment the close began.

A request carrying `Connection: close` was the common way to hit this: the server streamed a chunk, finished the response, and the connection closed in the same actor turn, so none of that response's callbacks arrived. An actor that waited for a callback before sending the next chunk, as `examples/streaming` does, stopped there, and the response was never finished.

The callback for a chunk whose bytes have already reached the operating system is no longer discarded when a close begins. It can now arrive while the connection is closing.

No callback fires until the chunk's bytes reach the operating system, and even then it can be lost: when the connection's close is reported first, any callback queued behind that report never reaches your actor. One way that happens is a callback and the close landing in the same actor turn, where the close is delivered synchronously and the callback is queued behind it (`ponylang/lori#345`). An actor that sends the next chunk only after the previous one's callback can still stall that way, leaving the response unfinished.

## Fix a possible write hang under load

Under write load, sending response data could hang the whole program. When the send buffer filled on a blocking file descriptor, the write stalled and never returned. Connections use non-blocking descriptors, so this was only reachable once the operating system had reused a closed connection's descriptor number for a blocking socket elsewhere in the process. Rare, but possible.

Sends now use a socket call, new in ponyc 0.67.0, that returns when the send buffer is full instead of stalling. The hang is closed on Linux, FreeBSD, OpenBSD, and DragonFly. macOS and Windows are unchanged.

## Remove HTTPServer.yield_read()

`yield_read()` is gone. It could not do what its name said. A yield only ever took effect at the end of a delivery, so every request carried by the read it was called from was parsed and answered anyway — and a single read carries as many pipelined requests as fit in the buffer. What it actually did was skip the tail of a read the connection was about to stop reading regardless.

It was also callable anywhere on the server object. Only a call from inside a request callback had a defined meaning; a call from a behavior, from `on_closed()`, or after close either yielded a later read you did not mean or did nothing at all.

Use `read_buffer_size` on `ServerConfig` instead. That is the value which actually bounds how much a connection does per scheduler turn.

```pony
// Before
fun ref on_request_complete(request': Request val, responder: Responder) =>
  responder.respond(response)
  if (_count % 5) == 0 then
    _http.yield_read()
  end

// After — set it once, when you build the config
match lori.MakeReadBufferSize(4096)
| let b: lori.ReadBufferSize =>
  ServerConfig(host, port where read_buffer_size' = b)
end
```

## Add read_buffer_size to ServerConfig

How many bytes a connection reads before it hands the scheduler back and resumes on a later turn. It defaults to 16KB, which is what connections used before and what they still use if you set nothing.

Lowering it bounds how much one connection does per turn, at the cost of more turns to get through the same data. Under sustained pipelined traffic that bound is what keeps one busy connection from monopolising a scheduler thread, because every request carried by a single read is parsed and answered before the connection gives the turn back.

```pony
match lori.MakeReadBufferSize(4096)
| let b: lori.ReadBufferSize =>
  ServerConfig("0.0.0.0", "80" where read_buffer_size' = b)
end
```

## Require ponyc 0.67.0 or later

Stallion now requires ponyc 0.67.0 or later on every platform. The previous minimum was 0.64.0, and 0.66.0 on Windows; 0.64.0 through 0.66.x are no longer supported. The write hang under load is closed by a socket call that ponyc added in 0.67.0.

## Move to ponylang/ssl 3.0.0

Stallion now requires ponylang/ssl 3.0.0, where it required 2.0.1. Stallion's own API is unchanged by the move: you build an `SSLContext val` and hand it to `HTTPServer.ssl` exactly as before.

Your own code can break if it picks up the new version. If your application does not declare ssl itself, it gets 3.0.0 through stallion, and your own `use "ssl/net"` or `use "ssl/crypto"` code is built against it. If your application does declare ssl, your declaration is the one that applies.

The twelve protocol-version primitives now spell their acronyms in full. They are the values passed to `SSLContext.set_min_proto_version` and `set_max_proto_version`, so if you pin a TLS version on the context you hand to `HTTPServer.ssl`, that call no longer compiles until you rename it:

```pony
// Before
ctx.set_min_proto_version(Tls1u2Version())?

// After
ctx.set_min_proto_version(TLS1u2Version())?
```

`SSLContext.alpn_set_resolver` also changed: it takes an `ALPNProtocolResolver val` where it took a `box`. Constructing a `Digest`, `Digest.final`, and `HmacSha256` are all partial and need a `?`. `SSLState` gained an `SSLDisposed` member, which breaks an exhaustive match on `SSL.state()`. And a reference typed `HashFn tag` no longer compiles, so type it `val` or `box`. See the ponylang/ssl 3.0.0 release notes for more on each.

## Change when on_closed() fires

`on_closed()` used to fire in the actor turn the close was started in. For a server closing on `keep_alive=false`, that was the same turn as the response. It now fires once the connection is closed. That change applies to closes the server starts; when the peer disconnects first, `on_closed()` fires when that close is reported, as it did before.

A connection in the middle of a graceful close is not closed. A graceful close does not finish until everything has been sent and the peer has closed its half; a hard close closes immediately.

For a close the server starts on a connection that is not under backpressure, the connection is closed once the peer closes its half. There is no timeout on that wait. For a close the server starts on a connection that is under backpressure — between `on_throttled()` and `on_unthrottled()` — the close is a hard close and `on_closed()` fires in that same turn.

To close without waiting on the peer, call `dispose()` on the server actor. `HTTPServerActor` is a `lori.TCPConnectionActor`, so it has `dispose()`: the connection is hard-closed and `on_closed()` is delivered in the dispose turn.

An application that releases resources in `on_closed()` now releases them when the peer closes the connection, not when the close started. A user timer that comes due after the server has started closing still fires, so an actor with a deadline still gets it and can call `dispose()` to close without waiting on the peer. An application that called `HTTPServer.close()` from inside `on_closed()` used to recurse without bound; that recursion is gone.

## Report a closed connection from Responder

`Responder.start_chunked_response()` and `Responder.send_chunk()` used to report success on a connection that was closed or closing, for a response or a chunk that was then dropped: `start_chunked_response()` returned `StreamingStarted`, and `send_chunk()` returned a `ChunkSendToken` for a chunk that never went out.

`start_chunked_response()` now returns a new `ConnectionClosed` when the connection is closed or closing, and `send_chunk()` returns `None`, which is what it already returns when the call was a no-op.

`ConnectionClosed` is a new member of the `StartChunkedResponseResult` union, alongside `StreamingStarted`, `ChunkedNotSupported` and `AlreadyResponded`. That is source-breaking: an exhaustive match on the union does not compile until you add the case. A match with an `else` is unaffected.

```pony
// Before
match \exhaustive\ responder.start_chunked_response(stallion.StatusOK, headers)
| stallion.StreamingStarted => responder.send_chunk("chunk 1\n")
| stallion.ChunkedNotSupported => responder.respond(fallback)
| stallion.AlreadyResponded => None
end

// After
match \exhaustive\ responder.start_chunked_response(stallion.StatusOK, headers)
| stallion.StreamingStarted => responder.send_chunk("chunk 1\n")
| stallion.ChunkedNotSupported => responder.respond(fallback)
| stallion.AlreadyResponded => None
| stallion.ConnectionClosed => None
end
```

On a connection that is closed or closing, an HTTP/1.0 request gets `ConnectionClosed` rather than `ChunkedNotSupported`, because falling back to `respond()` does not work there either. A `Responder` that has already responded still gets `AlreadyResponded`. `ConnectionClosed` starts nothing, so a second `start_chunked_response()` returns it again, and a `send_chunk()` after it returns `None`.

An actor called back at `on_chunk_sent()` while the connection is closing gets `None` from `send_chunk()` before it has been told anything is closing.
