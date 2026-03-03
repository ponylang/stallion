## Upgrade lori dependency to 0.10.0

The lori dependency has been updated from 0.9.0 to 0.10.0. This brings several changes that affect stallion users who create `TCPListener` instances directly:

**Default connection limit is now 100,000.** Previously, there was no default connection limit (unlimited). Pass `limit = None` to restore the old unlimited behavior:

```pony
// Restore unlimited connections (was the default in lori 0.9.0)
TCPListener(auth, host, port, this where limit = None)
```

**`MaxSpawn` is now a constrained type.** If you were passing a custom `limit` to `TCPListener`, the type has changed from a bare `U32` to a validated type constructed via `MakeMaxSpawn`:

Before:

```pony
// lori 0.9.0 — limit was (U32 | None)
_tcp_listener = TCPListener(auth, host, port, this where limit = 500)
```

After:

```pony
// lori 0.10.0 — limit is MaxSpawn, created via MakeMaxSpawn
match MakeMaxSpawn(500)
| let limit: MaxSpawn =>
  _tcp_listener = TCPListener(auth, host, port, this where limit = limit)
end
```

**New `ip_version` parameter.** `TCPListener.create` now accepts an `ip_version` parameter (`IP4`, `IP6`, or `DualStack`). The default is `DualStack`. If you need to restrict to a specific IP version:

```pony
TCPListener(auth, host, port, this where ip_version = IP4)
```

Lori 0.10.0 also includes bug fixes: the accept loop no longer spins on persistent errors, and the read loop correctly yields after exceeding the byte threshold.
