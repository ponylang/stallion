use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"

class \nodoc\ iso _TestPipelineCorrectness is UnitTest
  """
  Send 3 GET requests in one buffer. Server accumulates responders and
  responds in reverse order (2, 1, 0). Client verifies responses arrive
  in registration order (0, 1, 2).
  """
  fun name(): String => "server/pipeline correctness"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45882"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestPipelineServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestPipelineClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestPipelineConnectionClose is UnitTest
  """
  Send 2 pipelined requests, second has Connection: close. Verify both
  responses arrive, then the connection closes.
  """
  fun name(): String => "server/pipeline connection close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45883"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestHelloServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /2 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client = _TestPipelineCloseClient(h', port', request)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestStreamingResponse is UnitTest
  """
  Server uses chunked transfer encoding to stream a response. Client
  verifies the response has Transfer-Encoding: chunked and contains
  all chunks.
  """
  fun name(): String => "server/streaming response"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45884"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestStreamServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestStreamClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestMaxPendingOverflow is UnitTest
  """
  Configure max_pending_responses to 2. Use a server that responds to the
  first request but holds subsequent Responders. Send 4 pipelined requests.
  Verify:
  - The first request gets a 200 OK response (not overflow)
  - Eventually a 500 Internal Server Error arrives (overflow at request 4)
  - The connection closes
  """
  fun name(): String => "server/max pending overflow"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45885"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port where max_pending_responses' = 2)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestPartialRespondServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request: String val =
          "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /3 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /4 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let client = _TestMaxPendingClient(h', port', request)
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestHTTP10ChunkedRejection is UnitTest
  """
  Send an HTTP/1.0 request to a server that attempts chunked encoding
  then falls back to respond(). Verify that chunked is silently rejected
  (HTTP/1.0 doesn't support it) and the fallback respond() succeeds.
  """
  fun name(): String => "server/http 1.0 chunked rejection"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45886"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestChunkedFallbackServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let request = "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n"
        let client =
          _TestHTTPClient(
          h',
          port',
          request,
          "200 OK",
          "fallback")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestPipelineServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestPipelineServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestPipelineServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  embed _responders: Array[Responder]

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _responders = Array[Responder]
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _responders.push(responder)
    if _responders.size() == 3 then
      // Respond in reverse order (2, 1, 0)
      // Queue ensures delivery in registration order (0, 1, 2)
      try
        _respond(_responders(2)?, "response-2")
        _respond(_responders(1)?, "response-1")
        _respond(_responders(0)?, "response-0")
      end
    end

  fun ref _respond(responder: Responder, resp_body: String val) =>
    let response = ResponseBuilder(StatusOK)
      .add_header("content-type", "text/plain")
      .add_header("Content-Length", resp_body.size().string())
      .finish_headers()
      .add_chunk(resp_body)
      .build()
    responder.respond(response)

class \nodoc\ val _TestStreamServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestStreamServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestStreamServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers =
      recover val
        Headers .> set("content-type", "text/plain")
      end
    responder.start_chunked_response(StatusOK, headers)
    responder.send_chunk("chunk1")
    responder.send_chunk("chunk2")
    responder.send_chunk("chunk3")
    responder.finish_response()

actor \nodoc\ _TestPipelineClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _completed: Bool = false

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Send 3 pipelined requests in one buffer
    _tcp_connection.send(
      "GET /0 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
      "GET /2 HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Check if we have all 3 responses
    if r.contains("response-2") then
      _completed = true
      try
        let pos0 = r.find("response-0")?
        let pos1 = r.find("response-1")?
        let pos2 = r.find("response-2")?
        if (pos0 < pos1) and (pos1 < pos2) then
          _h.complete(true)
        else
          _h.fail("Responses arrived out of order: pos0="
            + pos0.string() + " pos1=" + pos1.string()
            + " pos2=" + pos2.string())
          _h.complete(false)
        end
      else
        _h.fail("Could not find all response bodies in:\n" + r)
        _h.complete(false)
      end
    end
    lori.KeepReading

  fun ref _on_closed() =>
    // A close after the test's outcome is decided is not a failure.
    if not _completed then
      _h.fail(
        "Connection closed before all three responses arrived:\n" + _response)
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

actor \nodoc\ _TestPipelineCloseClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  var _response: String ref = String
  var _got_responses: Bool = false

  new create(h: TestHelper, port: String, request: String val) =>
    _h = h
    _request = request
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Look for 2 occurrences of "Hello, World!"
    try
      r.find("Hello, World!", 0, 1)?  // Find 2nd occurrence (0-indexed nth)
      _got_responses = true
    end
    lori.KeepReading

  fun ref _on_closed() =>
    if _got_responses then
      _h.complete(true)
    else
      let r: String val = _response.clone()
      try
        r.find("Hello, World!", 0, 1)?
        _h.complete(true)
      else
        _h.fail(
          "Connection closed before both responses received:\n" + r)
        _h.complete(false)
      end
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

actor \nodoc\ _TestStreamClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _completed: Bool = false

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Check for terminal chunk
    if r.contains("0\r\n\r\n") then
      _completed = true
      // Verify Transfer-Encoding: chunked header (case-insensitive check)
      if not (r.contains("Transfer-Encoding: chunked")
        or r.contains("transfer-encoding: chunked"))
      then
        _h.fail(
          "Missing Transfer-Encoding: chunked header in:\n" + r)
        _h.complete(false)
        return lori.KeepReading
      end
      // Verify chunk data is present
      if not (r.contains("chunk1") and r.contains("chunk2")
        and r.contains("chunk3"))
      then
        _h.fail("Missing chunk data in:\n" + r)
        _h.complete(false)
        return lori.KeepReading
      end
      _h.complete(true)
    end
    lori.KeepReading

  fun ref _on_closed() =>
    // A close after the test's outcome is decided is not a failure.
    if not _completed then
      _h.fail(
        "Connection closed before the chunked response completed:\n"
          + _response)
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

class \nodoc\ val _TestPartialRespondServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestPartialRespondServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestPartialRespondServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  var _count: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    _count = _count + 1
    if _count == 1 then
      let resp_body: String val = "first-ok"
      let response = ResponseBuilder(StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", resp_body.size().string())
        .finish_headers()
        .add_chunk(resp_body)
        .build()
      responder.respond(response)
    end
    // Subsequent requests: intentionally never respond

actor \nodoc\ _TestMaxPendingClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  var _response: String ref = String
  var _got_ok: Bool = false
  var _got_500: Bool = false

  new create(h: TestHelper, port: String, request: String val) =>
    _h = h
    _request = request
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    if (not _got_ok) and r.contains("first-ok") then
      _got_ok = true
    end
    if (not _got_500) and r.contains("500 Internal Server Error") then
      _got_500 = true
    end
    lori.KeepReading

  fun ref _on_closed() =>
    if _got_ok and _got_500 then
      _h.complete(true)
    elseif not _got_ok then
      _h.fail("Never received initial 200 OK before overflow")
      _h.complete(false)
    elseif not _got_500 then
      _h.fail("Never received 500 overflow response")
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

class \nodoc\ val _TestChunkedFallbackServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestChunkedFallbackServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestChunkedFallbackServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers =
      recover val
        Headers .> set("content-type", "text/plain")
      end
    match \exhaustive\ responder.start_chunked_response(StatusOK, headers)
    | StreamingStarted =>
      responder.send_chunk("chunk1")
      responder.finish_response()
    | ChunkedNotSupported =>
      let fallback_body: String val = "fallback"
      let response = ResponseBuilder(StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", fallback_body.size().string())
        .finish_headers()
        .add_chunk(fallback_body)
        .build()
      responder.respond(response)
    | AlreadyResponded => None
    | ConnectionClosed => None
    end

class \nodoc\ iso _TestChunkSentCallback is UnitTest
  """
  Server uses `on_chunk_sent()` to drive subsequent chunks. Client sends a
  request, reads the complete chunked response, and verifies all chunks
  arrived. This exercises the full _on_sent -> HTTPServer -> actor chain.
  """
  fun name(): String => "server/on_chunk_sent callback"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45894"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestServerListener(
      h,
      port,
      _TestChunkSentServerFactory,
      config,
      {(h': TestHelper, port': String) =>
        let client = _TestChunkSentClient(h', port')
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestChunkSentServerFactory is _TestConnectionFactory
  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestChunkSentServer(auth, fd, config, ssl_ctx)

actor \nodoc\ _TestChunkSentServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  var _responder: (Responder | None) = None
  var _chunks_sent: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None))
  =>
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
      HTTPServer.ssl(auth, ctx, fd, this, config)
    else
      HTTPServer(auth, fd, this, config)
    end

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let headers =
      recover val
        Headers .> set("content-type", "text/plain")
      end
    responder.start_chunked_response(StatusOK, headers)
    _responder = responder
    _chunks_sent = 1
    responder.send_chunk("cs-chunk-1")

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    match _responder
    | let r: Responder =>
      _chunks_sent = _chunks_sent + 1
      if _chunks_sent <= 3 then
        r.send_chunk("cs-chunk-" + _chunks_sent.string())
      else
        r.finish_response()
        _responder = None
      end
    end

actor \nodoc\ _TestChunkSentClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  var _response: String ref = String
  var _completed: Bool = false

  new create(h: TestHelper, port: String) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      lori.TCPConnection.client(
      lori.TCPConnectAuth(_h.env.root), host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send(
      "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _response.append(consume data)
    let r: String val = _response.clone()
    // Check for terminal chunk
    if r.contains("0\r\n\r\n") then
      _completed = true
      if not (r.contains("Transfer-Encoding: chunked")
        or r.contains("transfer-encoding: chunked"))
      then
        _h.fail(
          "Missing Transfer-Encoding: chunked header in:\n" + r)
        _h.complete(false)
        return lori.KeepReading
      end
      // Verify all 3 chunks arrived
      if not (r.contains("cs-chunk-1") and r.contains("cs-chunk-2")
        and r.contains("cs-chunk-3"))
      then
        _h.fail("Missing chunk data in:\n" + r)
        _h.complete(false)
        return lori.KeepReading
      end
      _h.complete(true)
    end
    lori.KeepReading

  fun ref _on_closed() =>
    // A close after the test's outcome is decided is not a failure.
    if not _completed then
      _h.fail(
        "Connection closed before the chunked response completed:\n"
          + _response)
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

