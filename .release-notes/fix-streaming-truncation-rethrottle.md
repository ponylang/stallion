## Fix truncated streaming responses under sustained backpressure

A large streaming response (for example, a chunked Server-Sent Events stream to a slow client) could be silently truncated on the wire. The client received a partial response with no closing chunk, and the connection then closed — for instance, `curl` reported `transfer closed with N bytes remaining to read`.

This happened when the network applied backpressure, briefly relieved it, and then re-applied it while stallion was still flushing the buffered chunks. The chunks that had not yet been sent were dropped instead of being held back for the next time the connection could write. Finishing a response while backpressured could lose buffered data the same way. Both cases are fixed: buffered chunks now stay queued until they can actually be sent, and a response held back by backpressure completes once the connection drains.
