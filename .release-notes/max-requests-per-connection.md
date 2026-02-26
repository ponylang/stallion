## Add configurable max requests per keep-alive connection

`ServerConfig` now accepts a `max_requests_per_connection'` parameter that limits how many requests a single keep-alive connection can serve before the server closes it. This is analogous to nginx's `keepalive_requests` directive. The default is `None` (unlimited), preserving existing behavior. The limit value is a `MaxRequestsPerConnection` constrained type (must be at least 1), created via `MakeMaxRequestsPerConnection`.

```pony
match MakeMaxRequestsPerConnection(1000)
| let m: MaxRequestsPerConnection =>
  ServerConfig("0.0.0.0", "80" where max_requests_per_connection' = m)
end
```
