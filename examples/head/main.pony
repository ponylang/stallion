"""
HTTP server that handles HEAD correctly. A GET request gets a body; a HEAD
request gets the same headers a GET would, including Content-Length, but no
body, as required by RFC 9110.

Stallion sends exactly the bytes the handler builds and never rewrites a
response, so suppressing the body for HEAD is the handler's job. This example
shows the pattern: build the headers once, then add the body chunk only when
the method is not HEAD.

Try it:
  curl -i http://localhost:8080/      # GET: headers and body
  curl -I http://localhost:8080/      # HEAD: same headers, no body
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
    HeadServer(_server_auth, fd, _config)

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

actor HeadServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig)
  =>
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    // A HEAD response carries the same headers a GET would, including
    // Content-Length, but no body. Build the headers once, then add the body
    // chunk only when the method is not HEAD. Stallion sends exactly what we
    // build, so it is on us to leave the body off for HEAD.
    let body: String val = "Hello, World!"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", body.size().string())
      .finish_headers()
    if not (request'.method is stallion.HEAD) then
      response.add_chunk(body)
    end
    responder.respond(response.build())
