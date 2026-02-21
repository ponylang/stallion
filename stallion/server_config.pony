use lori = "lori"

primitive DefaultIdleTimeout
  """60-second idle timeout, the default for HTTP connections."""
  fun apply(): (lori.IdleTimeout | None) =>
    match lori.MakeIdleTimeout(60_000)
    | let t: lori.IdleTimeout => t
    else
      _Unreachable()
      None
    end

class val ServerConfig
  """
  Server-level configuration.

  Host and port specify the listen address. Parser limits control the maximum
  size of request components. Idle timeout controls how long a keep-alive
  connection can sit without activity before being closed.

  ```pony
  // All defaults (60-second idle timeout)
  ServerConfig("localhost", "8080")

  // Custom timeout via MakeIdleTimeout (milliseconds)
  let timeout = match lori.MakeIdleTimeout(30_000)
  | let t: lori.IdleTimeout => t
  end
  ServerConfig("0.0.0.0", "80" where
    max_body_size' = 10_485_760,  // 10 MB
    idle_timeout' = timeout)

  // Disable idle timeout
  ServerConfig("0.0.0.0", "80" where idle_timeout' = None)
  ```
  """
  let host: String
  let port: String
  let max_request_line_size: USize
  let max_header_size: USize
  let max_chunk_header_size: USize
  let max_body_size: USize
  let max_concurrent_connections: (U32 | None)
  let max_pending_responses: USize
  let idle_timeout: (lori.IdleTimeout | None)

  new val create(
    host': String,
    port': String,
    max_request_line_size': USize = 8192,
    max_header_size': USize = 8192,
    max_chunk_header_size': USize = 128,
    max_body_size': USize = 1_048_576,
    max_concurrent_connections': (U32 | None) = None,
    max_pending_responses': USize = 100,
    idle_timeout': (lori.IdleTimeout | None) = DefaultIdleTimeout())
  =>
    """
    Create server configuration.

    `host'` and `port'` specify the listen address. Parser limits default to
    sensible values. `idle_timeout'` is an `IdleTimeout` (milliseconds) or
    `None` to disable idle timeout. Defaults to 60 seconds. Use
    `lori.MakeIdleTimeout(ms)` to create custom timeout values.
    `max_concurrent_connections'` limits simultaneous connections (`None` for
    unlimited). `max_pending_responses'` limits the number of pipelined
    requests that can be outstanding before the connection closes — this
    prevents unbounded memory growth from actors that never respond.
    """
    host = host'
    port = port'
    max_request_line_size = max_request_line_size'
    max_header_size = max_header_size'
    max_chunk_header_size = max_chunk_header_size'
    max_body_size = max_body_size'
    max_concurrent_connections = max_concurrent_connections'
    max_pending_responses = max_pending_responses'
    idle_timeout = idle_timeout'

  fun _parser_config(): _ParserConfig val =>
    """Create a parser config from the parser limit fields."""
    _ParserConfig(
      max_request_line_size,
      max_header_size,
      max_chunk_header_size,
      max_body_size)
