"""
HTTP server that reads a small amount from each connection before handing
the scheduler back.

A connection reads up to its read buffer size in one scheduler turn; the
runtime reschedules it on a later turn. Under sustained pipelined
traffic that bound is what keeps one busy connection from monopolizing a
scheduler thread, because every request carried by a single read is parsed
and answered before the connection gives the turn back.

Demonstrates setting `read_buffer_size` on `ServerConfig`. The default is
16KB; this server uses 1KB, so it does roughly a sixteenth as much work per
turn and takes more turns to do it.

```
printf 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n%.0s' \
  {1..20} | nc localhost 8080
```
"""
