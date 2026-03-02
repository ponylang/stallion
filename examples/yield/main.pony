"""
HTTP server that yields the read loop every N requests for scheduler
fairness. Under sustained pipelined traffic a single connection's read
loop can monopolize the Pony scheduler; periodic `yield_read()` calls
give other actors a chance to run.

Demonstrates calling `HTTPServer.yield_read()` from `on_request_complete`
to implement a request-count-based yield policy. The yield is a one-shot
pause — the read loop resumes automatically in the next scheduler turn.

Try it with pipelined requests to see the yield in action:

```
printf 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n%.0s' {1..20} | nc localhost 8080
```
"""
use stallion = "../../stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    Listener(auth, "0.0.0.0", "8080", env.out)

actor Listener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _out: OutStream
  let _config: stallion.ServerConfig
  let _server_auth: lori.TCPServerAuth

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    YieldServer(_server_auth, fd, _config, _out)

  fun ref _on_listening() =>
    try
      (let host, let port) = _tcp_listener.local_address().name()?
      _out.print("Server listening on " + host + ":" + port)
    else
      _out.print("Server listening")
    end

  fun ref _on_listen_failure() =>
    _out.print("Failed to start server")

  fun ref _on_closed() =>
    _out.print("Server closed")

actor YieldServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _out: OutStream
  var _request_count: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig,
    out: OutStream)
  =>
    _out = out
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    _request_count = _request_count + 1
    let body: String val = "Request " + _request_count.string() + "\n"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)

    // Yield every 5 requests to let other actors run
    if (_request_count % 5) == 0 then
      _out.print("Yielding after request " + _request_count.string())
      _http.yield_read()
    end
