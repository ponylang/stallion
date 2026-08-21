use "pony_check"
use "pony_test"
use lori = "lori"
use ssl_net = "ssl/net"

class \nodoc\ iso _TestServerTimerFires is UnitTest
  """
  Deadline pattern where the timer fires before the worker responds.
  The server sets a short timer and delegates to a worker that never
  responds, so the timer fires and the server sends 408 Request Timeout.
  """
  fun name(): String => "server/timer fires"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45911"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let worker = _TestTimerWorker(false) // never responds
    let listener =
      _TestServerListener(
      h,
      port,
      _TestTimerServerFactory(worker),
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client =
          _TestHTTPClientExpectClose(
          h',
          port',
          request,
          "408 Request Timeout")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ iso _TestServerTimerCancelled is UnitTest
  """
  Deadline pattern where the worker responds before the timer fires.
  The server sets a long timer and delegates to a worker that responds
  immediately, so the timer is cancelled and the server sends the
  worker's result.
  """
  fun name(): String => "server/timer cancelled"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let port = "45912"
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let config = ServerConfig(host, port)
    let worker = _TestTimerWorker(true) // responds immediately
    let listener =
      _TestServerListener(
      h,
      port,
      _TestTimerServerFactory(worker),
      config,
      {(h': TestHelper, port': String) =>
        let request =
          "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let client = _TestHTTPClientExpectClose(h', port', request, "200 OK")
        h'.dispose_when_done(client)
      })
    h.dispose_when_done(listener)

class \nodoc\ val _TestTimerServerFactory is _TestConnectionFactory
  let _worker: _TestTimerWorker tag

  new val create(worker: _TestTimerWorker tag) =>
    _worker = worker

  fun apply(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    ssl_ctx: (ssl_net.SSLContext val | None)
  ): lori.TCPConnectionActor =>
    _TestTimerServer(auth, fd, config, _worker)

actor \nodoc\ _TestTimerWorker
  """
  Simulates async work. When `_respond` is true, calls back immediately.
  When false, never responds — simulating a hang.
  """
  let _respond: Bool

  new create(respond': Bool) =>
    _respond = respond'

  be process(server: _TestTimerServer tag) =>
    if _respond then
      server.work_complete("Hello, World!")
    end

actor \nodoc\ _TestTimerServer is HTTPServerActor
  var _http: HTTPServer = HTTPServer.none()
  let _worker: _TestTimerWorker tag
  var _responder: (Responder | None) = None
  var _timer_token: (lori.TimerToken | None) = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ServerConfig,
    worker: _TestTimerWorker tag)
  =>
    _worker = worker
    _http = HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): HTTPServer => _http

  fun ref on_request_complete(request': Request val, responder: Responder) =>
    // 2-second deadline. The worker's behavior (respond or hang)
    // determines which path wins — not the timer duration.
    match lori.MakeTimerDuration(2_000)
    | let d: lori.TimerDuration =>
      match _http.set_timer(d)
      | let t: lori.TimerToken =>
        _responder = responder
        _timer_token = t
        _worker.process(this)
      end
    end

  be work_complete(result: String val) =>
    // Worker finished before the deadline — cancel timer and respond
    match (_timer_token, _responder)
    | (let t: lori.TimerToken, let r: Responder) =>
      _http.cancel_timer(t)
      _timer_token = None
      _responder = None
      let response = ResponseBuilder(StatusOK)
        .add_header("Content-Type", "text/plain")
        .add_header("Content-Length", result.size().string())
        .add_header("Connection", "close")
        .finish_headers()
        .add_chunk(result)
        .build()
      r.respond(response)
    end

  fun ref on_timer(token: lori.TimerToken) =>
    // Deadline expired — worker didn't finish in time
    match (_timer_token, _responder)
    | (let t: lori.TimerToken, let r: Responder) if t == token =>
      _timer_token = None
      _responder = None
      let resp_body: String val = "Request timed out"
      let response = ResponseBuilder(StatusRequestTimeout)
        .add_header("Content-Type", "text/plain")
        .add_header("Content-Length", resp_body.size().string())
        .add_header("Connection", "close")
        .finish_headers()
        .add_chunk(resp_body)
        .build()
      r.respond(response)
    end

class \nodoc\ iso _PropertyKeepAliveDecision
  is Property1[(Version, (String val | None))]
  """
  The keep-alive decision matches the HTTP/1.x spec:
  - HTTP/1.1 + no header -> keep-alive
  - HTTP/1.1 + Connection: close (any case) -> close
  - HTTP/1.0 + no header -> close
  - HTTP/1.0 + Connection: keep-alive (any case) -> keep-alive
  - Unrecognized Connection values use version default
  """
  fun name(): String => "keep-alive/decision"

  fun gen(): Generator[(Version, (String val | None))] =>
    let version_gen =
      Generators.one_of[Version](
      [as Version: HTTP10; HTTP11])

    let known_gen: Generator[(String val | None)] =
      Generators.one_of[(String val | None)](
        [ as (String val | None):
          None; "close"; "Close"; "CLOSE"
          "keep-alive"; "Keep-Alive"; "KEEP-ALIVE"])

    // Single-token unrecognized values. The oracle below does not tokenize,
    // so a generated value must be a single token (no comma) that the
    // implementation also treats as unrecognized. The implementation
    // normalizes each token by stripping OWS (" \t") and lowercasing before
    // matching, and `ascii_printable` can emit SP/HTAB, so we exclude any
    // value whose normalized form is "close"/"keep-alive" — otherwise the
    // implementation recognizes it while the oracle does not. Multi-token and
    // close-precedence behavior is covered by _PropertyKeepAliveCloseAlwaysWins
    // and _TestKeepAliveMultiToken, which exercise the tokenizer.
    let random_gen: Generator[(String val | None)] =
      Generators.ascii_printable(1, 20)
        .filter(
          {(s: String val): (String val, Bool) =>
            let normalized = s.clone()
            normalized.strip(" \t")
            let nlower = normalized.lower()
            (s, (not s.contains(",")) and
              (nlower != "close") and
              (nlower != "keep-alive"))})
        .map[(String val | None)](
          {(s: String val): (String val | None) => s })

    let connection_gen =
      Generators.frequency[(String val | None)](
      [ as WeightedGenerator[(String val | None)]:
      (5, known_gen)
      (2, random_gen)
    ])

    Generators.zip2[Version, (String val | None)](
      version_gen, connection_gen)

  fun ref property(
    arg1: (Version, (String val | None)),
    ph: PropertyHelper)
  =>
    (let version, let connection) = arg1
    let result = _KeepAliveDecision(version, connection)

    match connection
    | let c: String =>
      let lower = c.lower()
      if lower == "close" then
        ph.assert_false(
          result,
          "Connection: close should always close")
        return
      end
      if lower == "keep-alive" then
        ph.assert_true(
          result,
          "Connection: keep-alive should always keep alive")
        return
      end
    end

    // No header or unrecognized value: version-dependent
    if version is HTTP11 then
      ph.assert_true(result, "HTTP/1.1 default should be keep-alive")
    else
      ph.assert_false(result, "HTTP/1.0 default should be close")
    end

class \nodoc\ iso _PropertyKeepAliveCloseAlwaysWins
  is Property1[(String val, Array[String val] ref, USize, Version)]
  """
  A `close` token anywhere in the Connection list closes the connection,
  regardless of HTTP version, token position, case, surrounding whitespace,
  or the presence of `keep-alive` (RFC 9112 §9.6 close precedence).

  Each sample builds a comma-separated list that always contains one `close`
  token (case/OWS varied) inserted at a varied position among filler tokens
  that may include `keep-alive`. The oracle is the constant `false` — it does
  not reimplement the tokenizer, so it cannot mirror an implementation bug.
  """
  fun name(): String => "keep-alive/close_always_wins"

  fun gen(): Generator[(String val, Array[String val] ref, USize, Version)] =>
    // `close` with varied case and surrounding optional whitespace (SP/HTAB).
    let close_gen =
      Generators.one_of[String val](
      [ as String val:
        "close"; "Close"; "CLOSE"; "cLoSe"
        " close "; "close "; "  close"; "\tclose\t"])
    // Filler tokens that are never `close`; `keep-alive` is included so the
    // property exercises close winning over a keep-alive token.
    let filler_gen =
      Generators.array_of[String val](
      Generators.one_of[String val](
        [as String val: "keep-alive"; "Keep-Alive"; "Upgrade"; "te"; "x-foo"]),
      0,
      4)
    // Insertion position for the close token (mod size+1 in the property).
    let pos_gen = Generators.usize(0, 8)
    let version_gen =
      Generators.one_of[Version](
      [as Version: HTTP10; HTTP11])
    Generators.zip4[String val, Array[String val] ref, USize, Version](
      close_gen, filler_gen, pos_gen, version_gen)

  fun ref property(
    arg1: (String val, Array[String val] ref, USize, Version),
    ph: PropertyHelper)
  =>
    (let close_tok, let fillers, let raw_pos, let version) = arg1
    let pos = raw_pos % (fillers.size() + 1)
    let tokens = Array[String val]
    var i: USize = 0
    for f in fillers.values() do
      if i == pos then tokens.push(close_tok) end
      tokens.push(f)
      i = i + 1
    end
    if pos == fillers.size() then tokens.push(close_tok) end

    let connection: String val = ",".join(tokens.values())
    ph.assert_false(
      _KeepAliveDecision(version, connection),
      "close anywhere must close; value was: " + connection)

class \nodoc\ iso _TestKeepAliveMultiToken is UnitTest
  """
  Multi-token and degenerate Connection values, decided by
  `_KeepAliveDecision`. Covers close precedence in both orders, real-world
  multi-token values, exact-token (never substring) matching, OWS and case
  handling, degenerate forms, and the version default — including the `None`
  (no header) case.
  """
  fun name(): String => "keep-alive/multi_token"

  fun apply(h: TestHelper) =>
    // (version, connection, expected keep-alive)
    let cases: Array[(Version, (String val | None), Bool)] =
      [ (HTTP11, None, true); (HTTP10, None, false)
        // close precedence, both orders, both versions
        (HTTP11, "keep-alive, close", false)
        (HTTP11, "close, keep-alive", false)
        (HTTP10, "keep-alive, close", false)
        (HTTP10, "close, keep-alive", false)
        // values from issue #105
        (HTTP11, "close, x-fake-option", false)
        (HTTP11, "x-fake-option, close", false)
        // real-world multi-token values
        (HTTP11, "keep-alive, Upgrade", true)
        (HTTP10, "keep-alive, Upgrade", true)
        (HTTP11, "close, TE", false)
        // exact-token matching, never substring -> version default
        (HTTP11, "closed", true)
        (HTTP11, "x-close", true)
        (HTTP10, "keep-alive-ish", false)
        // degenerate -> version default
        (HTTP11, "", true); (HTTP11, ",", true); (HTTP11, "   ", true)
        // leading/trailing comma around close
        (HTTP11, "close,", false); (HTTP11, ",close", false)
        // OWS and case
        (HTTP11, "  close  ", false); (HTTP11, "CLOSE", false)
        (HTTP11, "keep-alive , close", false)
        // all-unknown -> version default, both versions
        (HTTP10, "foo, bar", false); (HTTP11, "foo, bar", true) ]
    for (version, connection, expected) in cases.values() do
      let result = _KeepAliveDecision(version, connection)
      let shown =
        match \exhaustive\ connection
        | let s: String val => s
        | None => "None"
        end
      h.assert_eq[Bool](
        expected,
        result,
        "version=" + version.string() + " connection=" + shown)
    end

