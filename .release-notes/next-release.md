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

`Responder.send_chunk()` returns a `ChunkSendToken`, and `on_chunk_sent()` fires with that token once the chunk has been handed to the operating system. That pairing is what flow-controlled streaming is built on: send a chunk, wait for its callback, send the next. It did not hold. One callback was delivered each time the write queue drained completely rather than one per chunk, so an actor that sent several chunks while the socket was backed up got fewer callbacks than it had chunks outstanding.

An actor that drives the next chunk from `on_chunk_sent()`, which is what `examples/streaming` does, stops sending when a callback it is waiting on never arrives, and the response is never finished. Keeping more than one chunk in flight made this more likely, because that is exactly when several chunks drain together.

Every chunk that `send_chunk()` accepts now produces exactly one `on_chunk_sent()` callback, carrying that chunk's own token, in the order the chunks were sent.

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
