"""
Visit counter using cookies. Reads the `visits` cookie from the request,
increments it, and sets it back via `Set-Cookie`. Demonstrates both
`Request.cookies` for reading and `SetCookieBuilder` for writing cookies.

First visit returns "Visit #1", subsequent visits increment the counter.
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
    CookieServer(_server_auth, fd, _config)

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

actor CookieServer is stallion.HTTPServerActor
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
    // Read the visits cookie, defaulting to "0"
    var visits: U64 = 0
    match request'.cookies.get("visits")
    | let v: String val =>
      try visits = v.u64()? end
    end
    visits = visits + 1

    let resp_body: String val = "Visit #" + visits.string()

    // Build a Set-Cookie header to store the updated count
    let set_cookie = match stallion.SetCookieBuilder("visits",
        visits.string())
      .with_path("/")
      .with_http_only(false)
      .with_secure(false)
      .with_same_site(stallion.SameSiteLax)
      .build()
    | let sc: stallion.SetCookie val => sc
    | let err: stallion.SetCookieBuildError =>
      // Cookie name/value are always valid here, so this is unreachable
      _respond_error(responder)
      return
    end

    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .add_header("Set-Cookie", set_cookie.header_value())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

  fun _respond_error(responder: stallion.Responder ref) =>
    let body: String val = "Internal Server Error"
    let response = stallion.ResponseBuilder(
        stallion.StatusInternalServerError)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
