use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"

class \nodoc\ iso _TestChunkSentBeforeClose is UnitTest
  """
  Chunk delivery and on_closed timing across a close.

  One chunk on a connection that closes: start_chunked_response(),
  send_chunk(), finish_response() on a request carrying `Connection: close`.
  The server counts the tokens send_chunk() returned against the
  on_chunk_sent() callbacks it received and compares them from on_closed().

  These tests assert on the server side, so they need a TestHelper inside the
  server actor. _TestConnectionFactory.apply has no TestHelper parameter, so a
  factory that needs one holds it in a field and hands it to the actor it
  builds — the same shape as _TestStartFailureServerFactory.
  """
  fun name(): String => "server/chunk sent before close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45880"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestTrackingListener(
      h,
      port,
      _TestChunkCountServerFactory(h, 1),
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestPassiveClient(
          h',
          port',
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestChunkSentMultipleBeforeClose is UnitTest
  """
  Three chunks in flight in one turn on a connection that closes. Same
  assertion as `server/chunk sent before close`.
  """
  fun name(): String => "server/multiple chunks sent before close"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45890"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestTrackingListener(
      h,
      port,
      _TestChunkCountServerFactory(h, 3),
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestPassiveClient(
          h',
          port',
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestOnClosedAfterResponse is UnitTest
  """
  A complete response on a request carrying `Connection: close`. The server
  sets a flag on the line after respond() returns and asserts it from
  on_closed(), so the test fails if on_closed() fires while respond() is
  still running.
  """
  fun name(): String => "server/on_closed after response"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45881"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestTrackingListener(
      h,
      port,
      _TestOnClosedTimingServerFactory(h),
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestPassiveClient(
          h',
          port',
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestChunkSentPipelinedNonHead is UnitTest
  """
  Two pipelined requests,
  the second carrying `Connection: close`. The server
  streams a chunk on the second responder while it is behind the head, so the
  chunk buffers, then answers the first and lets the queue cascade. Same
  assertion as `server/chunk sent before close`.
  """
  fun name(): String => "server/chunk sent on pipelined non-head response"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45897"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestTrackingListener(
      h,
      port,
      _TestPipelinedChunkServerFactory(h),
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestPassiveClient(
          h',
          port',
          "GET /1 HTTP/1.1\r\nHost: localhost\r\n\r\n" +
          "GET /2 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

actor \nodoc\ _TestTrackingListener is lori.TCPListenerActor
  """
  Test listener that keeps every server actor it accepts and disposes them
  when it closes. `_TestServerListener` keeps none, and it is shared by every
  other server test, so the tests that need disposal use this one.
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _connection_factory: _TestConnectionFactory
  let _config: ServerConfig
  let _h: TestHelper
  let _port: String
  let _start_client: {(TestHelper, String)} val
  embed _connections: Array[lori.TCPConnectionActor]

  new create(
    h: TestHelper,
    port: String,
    connection_factory: _TestConnectionFactory,
    config: ServerConfig,
    start_client: {(TestHelper, String)} val)
  =>
    _h = h
    _port = port
    _connection_factory = connection_factory
    _config = config
    _start_client = start_client
    _connections = Array[lori.TCPConnectionActor]
    let listen_auth = lori.TCPListenAuth(_h.env.root)
    _server_auth = lori.TCPServerAuth(listen_auth)
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_listener = lori.TCPListener(listen_auth, host, port, this)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    let conn = _connection_factory(_server_auth, fd, _config, None)
    _connections.push(conn)
    conn

  fun ref _on_listening() =>
    _start_client(_h, _port)

  fun ref _on_listen_failure() =>
    _h.fail("Listener failed to start on port " + _port)
    _h.complete(false)

  fun ref _on_closed() =>
    for conn in _connections.values() do
      conn.dispose()
    end
    _connections.clear()

actor \nodoc\ _TestPassiveClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  Test client that sends a request and then holds its socket open, discarding
  whatever comes back. It never closes first: a client that half-closes right
  after its request can put the response and the peer's close in one server
  turn, where a chunk's delivery callback is legitimately lost. It closes in
  response to the server's close, which is what lets the server's
  `on_closed()` fire; the tests that use this client assert and complete
  there.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val
  var _bytes_received: USize = 0

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
    _bytes_received = _bytes_received + data.size()
    lori.KeepReading

  fun ref _on_closed() =>
    // The server completes these tests from its own `on_closed()`, which it
    // only reaches after this client closes in response to the server's
    // close. A connection that ends before any response arrived never gets
    // there, so say that here rather than leaving the test to time out.
    if _bytes_received == 0 then
      _h.fail("Connection closed before any response arrived")
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)

class \nodoc\ val _TestChunkCountServerFactory is _TestConnectionFactory
  let _h: TestHelper
  let _chunks: USize

  new val create(h: TestHelper, chunks: USize) =>
    _h = h
    _chunks = chunks

  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestChunkCountServer(auth, fd, config, _h, _chunks)

actor \nodoc\ _TestChunkCountServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  let _h: TestHelper
  let _chunks: USize
  embed _sent: Array[ChunkSendToken]
  embed _delivered: Array[ChunkSendToken]

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    h: TestHelper,
    chunks: USize)
  =>
    _h = h
    _chunks = chunks
    _sent = Array[ChunkSendToken]
    _delivered = Array[ChunkSendToken]
    _http = HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    responder.start_chunked_response(StatusOK)
    var i: USize = 0
    while i < _chunks do
      match responder.send_chunk("chunk-" + i.string())
      | let t: ChunkSendToken => _sent.push(t)
      end
      i = i + 1
    end
    responder.finish_response()

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    _delivered.push(token)

  fun ref on_closed() =>
    _h.assert_eq[USize](
      _chunks,
      _sent.size(),
      "send_chunk() should have accepted every chunk")
    _h.assert_eq[USize](
      _sent.size(),
      _delivered.size(),
      "every chunk send_chunk() accepted should get an on_chunk_sent()")
    for (i, expected) in _sent.pairs() do
      try
        _h.assert_true(
          expected == _delivered(i)?,
          "on_chunk_sent() token " + i.string() + " should be the token "
            + "send_chunk() returned for that chunk")
      else
        _h.fail("missing on_chunk_sent() for chunk " + i.string())
      end
    end
    _h.complete(true)

class \nodoc\ val _TestOnClosedTimingServerFactory is _TestConnectionFactory
  let _h: TestHelper

  new val create(h: TestHelper) =>
    _h = h

  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestOnClosedTimingServer(auth, fd, config, _h)

actor \nodoc\ _TestOnClosedTimingServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  let _h: TestHelper
  var _responded: Bool = false
  var _closed_count: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    h: TestHelper)
  =>
    _h = h
    _http = HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    let resp_body: String val = "Hello, World!"
    responder.respond(
      ResponseBuilder(StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", resp_body.size().string())
        .finish_headers()
        .add_chunk(resp_body)
        .build())
    _responded = true

  fun ref on_closed() =>
    _closed_count = _closed_count + 1
    _h.assert_true(
      _responded,
      "on_closed() fired while respond() was still running")
    _http.close()
    _h.assert_eq[USize](
      1,
      _closed_count,
      "close() from on_closed() should not deliver on_closed() again")
    _h.complete(true)

class \nodoc\ val _TestPipelinedChunkServerFactory is _TestConnectionFactory
  let _h: TestHelper

  new val create(h: TestHelper) =>
    _h = h

  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestPipelinedChunkServer(auth, fd, config, _h)

actor \nodoc\ _TestPipelinedChunkServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  let _h: TestHelper
  var _head: (Responder | None) = None
  var _tokens: USize = 0
  var _callbacks: USize = 0

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    h: TestHelper)
  =>
    _h = h
    _http = HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    match \exhaustive\ _head
    | None =>
      _head = responder
    | let head: Responder =>
      responder.start_chunked_response(StatusOK)
      match responder.send_chunk("pipelined-chunk")
      | let _: ChunkSendToken => _tokens = _tokens + 1
      end
      responder.finish_response()
      _head = None
      let resp_body: String val = "head"
      head.respond(
        ResponseBuilder(StatusOK)
          .add_header("content-type", "text/plain")
          .add_header("Content-Length", resp_body.size().string())
          .finish_headers()
          .add_chunk(resp_body)
          .build())
    end

  fun ref on_chunk_sent(token: ChunkSendToken) =>
    _callbacks = _callbacks + 1

  fun ref on_closed() =>
    _h.assert_eq[USize](
      1,
      _tokens,
      "send_chunk() should have accepted the buffered chunk")
    _h.assert_eq[USize](
      _tokens,
      _callbacks,
      "every chunk send_chunk() accepted should get an on_chunk_sent()")
    _h.complete(true)

class \nodoc\ iso _TestTimerFiresWhileClosing is UnitTest
  """
  A timer set while the connection was active still fires after the server
  starts closing. The client mutes itself after sending,
  so it never reads
  the server's close and the server stays in its closing state; the timer
  then fires there and the server completes from `on_timer()`.
  """
  fun name(): String => "server/timer fires while closing"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45898"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let listener =
      _TestTrackingListener(
      h,
      port,
      _TestClosingTimerServerFactory(h),
      config,
      {(h': TestHelper, port': String) =>
        let client =
          _TestMutingClient(
          h',
          port',
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestClosingTimerServerFactory is _TestConnectionFactory
  let _h: TestHelper

  new val create(h: TestHelper) =>
    _h = h

  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestClosingTimerServer(auth, fd, config, _h)

actor \nodoc\ _TestClosingTimerServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  let _h: TestHelper
  var _armed: Bool = false

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    h: TestHelper)
  =>
    _h = h
    _http = HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    // Arm before responding: responding is what starts the close, and a
    // timer cannot be set once the connection is closing.
    match lori.MakeTimerDuration(200)
    | let d: lori.TimerDuration =>
      match _http.set_timer(d)
      | let t: lori.TimerToken => _armed = true
      end
    end
    if not _armed then
      _h.fail("could not set a timer on an active connection")
      _h.complete(false)
      return
    end
    let resp_body: String val = "Hello, World!"
    responder.respond(
      ResponseBuilder(StatusOK)
        .add_header("content-type", "text/plain")
        .add_header("Content-Length", resp_body.size().string())
        .finish_headers()
        .add_chunk(resp_body)
        .build())

  fun ref on_timer(token: lori.TimerToken) =>
    _h.complete(true)

actor \nodoc\ _TestMutingClient is
  (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  """
  Test client that sends a request and then mutes, so it never reads the
  response or the server's close. That holds the server in its closing state
  for as long as the test needs.
  """
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  let _h: TestHelper
  let _request: String val

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
    _tcp_connection.mute()

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("Client connection failed")
    _h.complete(false)
