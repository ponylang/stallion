# stallion

An HTTP server for Pony, built on [lori](https://github.com/ponylang/lori). Your actor IS the connection — no hidden internal actors, no notify objects. Responses are built with `ResponseBuilder` for complete responses, or streamed with flow-controlled chunked transfer encoding.

## Status

stallion is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/stallion.git --version 0.2.0`
* `corral fetch` to fetch your dependencies
* `use "stallion"` to include this package
* `corral run -- ponyc` to compile your application

You'll also need a SSL library installed on your platform. See the [net-ssl](https://github.com/ponylang/net-ssl) installation instructions for details.

## Usage

A stallion server has two actor types: a listener and one or more connection actors. The listener implements `lori.TCPListenerActor` and creates connection actors in `_on_accept`. Each connection actor implements `stallion.HTTPServerActor`, owns a `stallion.HTTPServer`, and overrides callbacks to handle requests:

```pony
use stallion = "stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    MyListener(auth, "localhost", "8080")

actor MyListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig

  new create(auth: lori.TCPListenAuth, host: String, port: String) =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    MyServer(_server_auth, fd, _config)

actor MyServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: stallion.ServerConfig)
  =>
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    let body: String val = "Hello!"
    let response = stallion.ResponseBuilder(stallion.StatusOK)
      .add_header("Content-Length", body.size().string())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
```

For streaming responses, use chunked transfer encoding with flow-controlled delivery via `on_chunk_sent()` callbacks. For HTTPS, use `stallion.HTTPServer.ssl` instead of `stallion.HTTPServer`. See the [examples](examples/) for complete working programs demonstrating query parameter extraction, SSL/TLS, and streaming.

## API Documentation

[https://ponylang.github.io/stallion](https://ponylang.github.io/stallion)
