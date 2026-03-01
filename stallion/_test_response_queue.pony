use "collections"
use "pony_check"
use "pony_test"

class \nodoc\ ref _TestQueueNotify is _ResponseQueueNotify
  """
  Test double that records all queue callback invocations for assertion.
  """
  embed flushed_data: Array[ByteSeq]
  embed flushed_tokens: Array[(ChunkSendToken | None)]
  embed completions: Array[Bool]
  var close_on_complete: Bool = false
  var close_on_flush_data: Bool = false
  var flush_data_close_trigger: String val = ""

  // Set by test to trigger close() on _response_complete (when keep_alive
  // is false) or on _flush_data (when data matches the trigger string),
  // simulating the connection closing due to send errors.
  var queue: (_ResponseQueue | None) = None

  new ref create() =>
    flushed_data = Array[ByteSeq]
    flushed_tokens = Array[(ChunkSendToken | None)]
    completions = Array[Bool]

  fun ref _flush_data(data: ByteSeq,
    token: (ChunkSendToken | None) = None)
  =>
    flushed_data.push(data)
    flushed_tokens.push(token)
    if close_on_flush_data then
      let s: String val = match \exhaustive\ data
      | let sv: String val => sv
      | let a: Array[U8] val => String.from_array(a)
      end
      if s == flush_data_close_trigger then
        match queue
        | let q: _ResponseQueue => q.close()
        end
      end
    end

  fun ref _response_complete(keep_alive: Bool) =>
    completions.push(keep_alive)
    if close_on_complete and (not keep_alive) then
      match queue
      | let q: _ResponseQueue => q.close()
      end
    end

  fun flushed_as_strings(): Array[String val] ref =>
    """Convert all flushed data to strings for easier assertion."""
    let result = Array[String val](flushed_data.size())
    for data in flushed_data.values() do
      match \exhaustive\ data
      | let s: String val => result.push(s)
      | let a: Array[U8] val => result.push(String.from_array(a))
      end
    end
    result

// ---------------------------------------------------------------------------
// Property-based test: in-order delivery
// ---------------------------------------------------------------------------

class \nodoc\ iso _PropertyQueueInOrderDelivery
  is Property1[Array[USize] val]
  """
  Register N entries, submit responses in a random permutation order.
  Verify that _flush_data calls arrive in registration order.
  """
  fun name(): String => "response-queue/in-order delivery"

  fun gen(): Generator[Array[USize] val] =>
    // Generate a count N (2..20), then a permutation of 0..N-1
    Generators.usize(2, 20).flat_map[Array[USize] val](
      {(n: USize): Generator[Array[USize] val] =>
        // Generate a shuffled array of 0..n-1
        _PermutationGenerator(n)
      })

  fun ref property(arg1: Array[USize] val, ph: PropertyHelper) =>
    let n = arg1.size()
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    // Register N entries, each with a unique body
    let ids = Array[U64](n)
    for i in Range(0, n) do
      ids.push(queue.register(true))
    end

    // Submit responses in permutation order
    for i in arg1.values() do
      try
        let id = ids(i)?
        let body: String val = i.string()
        queue.send_data(id, body)
        queue.finish(id)
      end
    end

    // Verify flush order matches registration order (0, 1, 2, ...)
    let flushed = notify.flushed_as_strings()
    ph.assert_eq[USize](n, flushed.size(),
      "Expected " + n.string() + " flushes, got " + flushed.size().string())
    for i in Range(0, n) do
      try
        ph.assert_eq[String val](i.string(), flushed(i)?,
          "Flush order mismatch at position " + i.string())
      end
    end

    // Verify all completions fired
    ph.assert_eq[USize](n, notify.completions.size(),
      "Expected " + n.string() + " completions")

class \nodoc\ iso _PropertyQueueMixedResponses
  is Property1[(USize, Array[USize] val)]
  """
  Register N entries, send multiple chunks per entry, finish all in
  random permutation order. Verify all data flushes in registration
  order (entry 0's chunks before entry 1's, etc.) and all completions
  fire.
  """
  fun name(): String => "response-queue/mixed responses"

  fun gen(): Generator[(USize, Array[USize] val)] =>
    Generators.usize(2, 15).flat_map[(USize, Array[USize] val)](
      {(n: USize): Generator[(USize, Array[USize] val)] =>
        _PermutationGenerator(n)
          .map[(USize, Array[USize] val)](
            {(perm: Array[USize] val): (USize, Array[USize] val) =>
              (n, perm)
            })
      })

  fun ref property(
    arg1: (USize, Array[USize] val),
    ph: PropertyHelper)
  =>
    (let n, let perm) = arg1
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let ids = Array[U64](n)
    for i in Range(0, n) do
      ids.push(queue.register(true))
    end

    // Send 2 chunks per entry (entry 0 is head, sent immediately;
    // others are buffered until they become head)
    for i in Range(0, n) do
      try
        let id = ids(i)?
        let data1: String val = "chunk1-" + i.string()
        let data2: String val = "chunk2-" + i.string()
        queue.send_data(id, data1)
        queue.send_data(id, data2)
      end
    end

    // Finish all in permutation order
    for i in perm.values() do
      try queue.finish(ids(i)?) end
    end

    // All N entries should have completed
    ph.assert_eq[USize](n, notify.completions.size(),
      "All entries should have completed")

    // Verify flush ordering: chunks appear in registration order
    let flushed = notify.flushed_as_strings()
    ph.assert_eq[USize](n * 2, flushed.size(),
      "Expected " + (n * 2).string() + " flushes")
    for i in Range(0, n) do
      try
        let expected1: String val = "chunk1-" + i.string()
        let expected2: String val = "chunk2-" + i.string()
        ph.assert_eq[String val](expected1, flushed(i * 2)?,
          "Flush order mismatch at position " + (i * 2).string())
        ph.assert_eq[String val](expected2, flushed((i * 2) + 1)?,
          "Flush order mismatch at position " + ((i * 2) + 1).string())
      end
    end

// ---------------------------------------------------------------------------
// Example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestQueueReverseOrder is UnitTest
  """
  Register 3 entries. Finish in order 2, 0, 1. Verify flush order is 0, 1, 2.
  """
  fun name(): String => "response-queue/reverse order"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id0 = queue.register(true)
    let id1 = queue.register(true)
    let id2 = queue.register(true)

    queue.send_data(id0, "resp-0")
    queue.send_data(id1, "resp-1")
    queue.send_data(id2, "resp-2")

    // Finish in reverse order
    queue.finish(id2)
    queue.finish(id0)  // This is the head — should cascade
    queue.finish(id1)

    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](3, flushed.size())
    try
      h.assert_eq[String val]("resp-0", flushed(0)?)
      h.assert_eq[String val]("resp-1", flushed(1)?)
      h.assert_eq[String val]("resp-2", flushed(2)?)
    else
      h.fail("Index out of bounds in flush assertions")
    end

    h.assert_eq[USize](3, notify.completions.size())

class \nodoc\ iso _TestQueueKeepAliveFalseStopsFlush is UnitTest
  """
  Register 2 entries with entry 0 having keep_alive=false. Finish both.
  Verify entry 0 flushes and _response_complete(false) fires, then
  entry 1 is discarded (via close triggered by the test notify).
  """
  fun name(): String => "response-queue/keep-alive false stops flush"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)
    notify.close_on_complete = true
    notify.queue = queue

    let id0 = queue.register(false)  // keep_alive = false
    let id1 = queue.register(true)

    queue.send_data(id0, "resp-0")
    queue.send_data(id1, "resp-1")
    queue.finish(id1)
    queue.finish(id0)

    // Only entry 0 should have flushed
    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](1, flushed.size())
    try
      h.assert_eq[String val]("resp-0", flushed(0)?)
    else
      h.fail("Index out of bounds")
    end

    // Only one completion (entry 0 with keep_alive=false)
    h.assert_eq[USize](1, notify.completions.size())
    try
      h.assert_eq[Bool](false, notify.completions(0)?)
    else
      h.fail("Completion index out of bounds")
    end

class \nodoc\ iso _TestQueueStreamingHead is UnitTest
  """
  Register 1 entry. Send 3 chunks, then finish. Verify 3 _flush_data
  calls followed by _response_complete.
  """
  fun name(): String => "response-queue/streaming head"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id = queue.register(true)

    queue.send_data(id, "chunk-1")
    queue.send_data(id, "chunk-2")
    queue.send_data(id, "chunk-3")
    queue.finish(id)

    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](3, flushed.size())
    try
      h.assert_eq[String val]("chunk-1", flushed(0)?)
      h.assert_eq[String val]("chunk-2", flushed(1)?)
      h.assert_eq[String val]("chunk-3", flushed(2)?)
    else
      h.fail("Chunk assertion index out of bounds")
    end

    h.assert_eq[USize](1, notify.completions.size())

class \nodoc\ iso _TestQueueStreamingNonHead is UnitTest
  """
  Register 2 entries. Stream chunks to entry 1, finish entry 1.
  Then finish entry 0. Verify: entry 0 data flushes first, then
  all of entry 1's buffered chunks flush.
  """
  fun name(): String => "response-queue/streaming non-head"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id0 = queue.register(true)
    let id1 = queue.register(true)

    // Stream chunks to entry 1 (non-head, so they buffer)
    queue.send_data(id1, "e1-chunk-1")
    queue.send_data(id1, "e1-chunk-2")
    queue.send_data(id1, "e1-chunk-3")
    queue.finish(id1)

    // Send data and finish entry 0 (head)
    queue.send_data(id0, "e0-data")
    queue.finish(id0)

    // Verify flush order: e0-data first, then e1 chunks
    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](4, flushed.size())
    try
      h.assert_eq[String val]("e0-data", flushed(0)?)
      h.assert_eq[String val]("e1-chunk-1", flushed(1)?)
      h.assert_eq[String val]("e1-chunk-2", flushed(2)?)
      h.assert_eq[String val]("e1-chunk-3", flushed(3)?)
    else
      h.fail("Flush order assertion index out of bounds")
    end

    h.assert_eq[USize](2, notify.completions.size())

class \nodoc\ iso _TestQueueThrottleUnthrottle is UnitTest
  """
  Register head, throttle, send data (should buffer), unthrottle
  (should flush buffered data).
  """
  fun name(): String => "response-queue/throttle-unthrottle"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id = queue.register(true)

    // Throttle before sending
    queue.throttle()
    queue.send_data(id, "throttled-data")

    // Nothing should have flushed yet
    h.assert_eq[USize](0, notify.flushed_data.size(),
      "Data should be buffered while throttled")

    // Unthrottle — buffered data should flush
    queue.unthrottle()

    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](1, flushed.size())
    try
      h.assert_eq[String val]("throttled-data", flushed(0)?)
    else
      h.fail("Throttle flush assertion index out of bounds")
    end

class \nodoc\ iso _TestQueueCloseOnFlushData is UnitTest
  """
  Register 2 entries. Finish entry 1 (non-head, buffers). Finish entry 0
  (head). During the cascade flush, _flush_data sees entry 1's data and
  triggers close(). Verify the cascade stops cleanly instead of crashing
  at _Unreachable() in _advance_head().
  """
  fun name(): String => "response-queue/close on flush data"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)
    notify.close_on_flush_data = true
    notify.flush_data_close_trigger = "e1-data"
    notify.queue = queue

    let id0 = queue.register(true)
    let id1 = queue.register(true)

    // Entry 1 (non-head): send data and finish — buffers and marks finished
    queue.send_data(id1, "e1-data")
    queue.finish(id1)

    // Entry 0 (head): send data and finish — triggers cascade
    // _advance_head removes entry 0, then _flush_new_head flushes entry 1's
    // buffered data. _flush_data("e1-data") triggers close(). Without the
    // fix, _advance_head() would crash on the empty _entries array.
    queue.send_data(id0, "e0-data")
    queue.finish(id0)

    // Verify entry 0's data flushed (it was head, sent immediately)
    // and entry 1's data flushed during cascade (triggering close)
    let flushed = notify.flushed_as_strings()
    h.assert_eq[USize](2, flushed.size())
    try
      h.assert_eq[String val]("e0-data", flushed(0)?)
      h.assert_eq[String val]("e1-data", flushed(1)?)
    else
      h.fail("Flush assertion index out of bounds")
    end

    // Entry 0's completion should have fired before the cascade
    h.assert_eq[USize](1, notify.completions.size())

// ---------------------------------------------------------------------------
// Token threading tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestQueueTokenImmediateFlush is UnitTest
  """
  Head entry: send data with a token, verify the token appears in the
  _flush_data callback immediately.
  """
  fun name(): String => "response-queue/token immediate flush"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id = queue.register(true)
    let token = queue.create_chunk_token()
    queue.send_data(id, "chunk-data", token)

    h.assert_eq[USize](1, notify.flushed_tokens.size())
    try
      match notify.flushed_tokens(0)?
      | let ct: ChunkSendToken =>
        h.assert_true(ct == token, "Token should match")
      else
        h.fail("Expected ChunkSendToken, got None")
      end
    else
      h.fail("Token index out of bounds")
    end

class \nodoc\ iso _TestQueueTokenBufferedFlush is UnitTest
  """
  Non-head entry: send data with a token, finish head, verify the token
  appears in the deferred flush.
  """
  fun name(): String => "response-queue/token buffered flush"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id0 = queue.register(true)
    let id1 = queue.register(true)

    // Send data with token to non-head entry (buffers)
    let token = queue.create_chunk_token()
    queue.send_data(id1, "e1-data", token)

    // Nothing should have flushed for entry 1 yet
    h.assert_eq[USize](0, notify.flushed_tokens.size())

    // Finish head entry to trigger cascade
    queue.send_data(id0, "e0-data")
    queue.finish(id0)
    queue.finish(id1)

    // Verify both data items flushed: e0-data (None token), e1-data (token)
    h.assert_eq[USize](2, notify.flushed_tokens.size())
    try
      match \exhaustive\ notify.flushed_tokens(0)?
      | let _: ChunkSendToken => h.fail("Head entry should have None token")
      | None => None  // expected
      end
      match \exhaustive\ notify.flushed_tokens(1)?
      | let ct: ChunkSendToken =>
        h.assert_true(ct == token, "Buffered token should match")
      else
        h.fail("Expected ChunkSendToken for entry 1, got None")
      end
    else
      h.fail("Token index out of bounds")
    end

class \nodoc\ iso _TestQueueTokenNoneForInternalSends is UnitTest
  """
  Mix of token and None sends. Verify each _flush_data gets the correct
  token value.
  """
  fun name(): String => "response-queue/token none for internal sends"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id = queue.register(true)
    let token = queue.create_chunk_token()

    // Internal send (headers — no token)
    queue.send_data(id, "headers")
    // User chunk (with token)
    queue.send_data(id, "chunk", token)
    // Internal send (terminal chunk — no token)
    queue.send_data(id, "0\r\n\r\n")
    queue.finish(id)

    h.assert_eq[USize](3, notify.flushed_tokens.size())
    try
      match notify.flushed_tokens(0)?
      | let _: ChunkSendToken =>
        h.fail("Headers should have None token")
      end
      match notify.flushed_tokens(1)?
      | let ct: ChunkSendToken =>
        h.assert_true(ct == token, "Chunk token should match")
      else
        h.fail("Chunk should have ChunkSendToken")
      end
      match notify.flushed_tokens(2)?
      | let _: ChunkSendToken =>
        h.fail("Terminal chunk should have None token")
      end
    else
      h.fail("Token index out of bounds")
    end

class \nodoc\ iso _TestQueueTokenThrottle is UnitTest
  """
  Throttle, send with token, unthrottle. Verify token survives buffering.
  """
  fun name(): String => "response-queue/token throttle"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id = queue.register(true)
    let token = queue.create_chunk_token()

    queue.throttle()
    queue.send_data(id, "throttled-chunk", token)

    // Nothing flushed yet
    h.assert_eq[USize](0, notify.flushed_tokens.size())

    queue.unthrottle()

    h.assert_eq[USize](1, notify.flushed_tokens.size())
    try
      match notify.flushed_tokens(0)?
      | let ct: ChunkSendToken =>
        h.assert_true(ct == token, "Token should survive throttle")
      else
        h.fail("Expected ChunkSendToken after unthrottle")
      end
    else
      h.fail("Token index out of bounds")
    end

class \nodoc\ iso _TestQueueTokenClose is UnitTest
  """
  Throttle, send with token, close, unthrottle. Verify no flush occurs.
  """
  fun name(): String => "response-queue/token close"

  fun apply(h: TestHelper) =>
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    let id = queue.register(true)
    let token = queue.create_chunk_token()

    queue.throttle()
    queue.send_data(id, "will-be-lost", token)
    queue.close()
    queue.unthrottle()

    // Nothing should have flushed — queue was closed
    h.assert_eq[USize](0, notify.flushed_tokens.size())
    h.assert_eq[USize](0, notify.flushed_data.size())

// ---------------------------------------------------------------------------
// Property-based test: token ordering
// ---------------------------------------------------------------------------

class \nodoc\ iso _PropertyQueueTokenOrder
  is Property1[Array[USize] val]
  """
  Register N entries, each with 1 None send (simulated headers) + 1 token
  send (simulated chunk) + 1 None send (simulated terminal). Finish in
  random permutation order. Verify all tokens flush in registration order.
  """
  fun name(): String => "response-queue/token order"

  fun gen(): Generator[Array[USize] val] =>
    Generators.usize(2, 15).flat_map[Array[USize] val](
      {(n: USize): Generator[Array[USize] val] =>
        _PermutationGenerator(n)
      })

  fun ref property(arg1: Array[USize] val, ph: PropertyHelper) =>
    let n = arg1.size()
    let notify = _TestQueueNotify
    let queue = _ResponseQueue(notify)

    // Register N entries, each with headers + chunk (token) + terminal
    let ids = Array[U64](n)
    let tokens = Array[ChunkSendToken](n)
    for i in Range(0, n) do
      let id = queue.register(true)
      ids.push(id)
      // Headers (no token)
      queue.send_data(id, "headers-" + i.string())
      // User chunk (with token)
      let token = queue.create_chunk_token()
      tokens.push(token)
      queue.send_data(id, "chunk-" + i.string(), token)
      // Terminal chunk (no token)
      queue.send_data(id, "terminal-" + i.string())
    end

    // Finish in permutation order
    for i in arg1.values() do
      try queue.finish(ids(i)?) end
    end

    // Extract only the ChunkSendTokens from the flushed tokens
    let flushed_chunk_tokens = Array[ChunkSendToken](n)
    for ft in notify.flushed_tokens.values() do
      match ft
      | let ct: ChunkSendToken => flushed_chunk_tokens.push(ct)
      end
    end

    ph.assert_eq[USize](n, flushed_chunk_tokens.size(),
      "Expected " + n.string() + " chunk tokens")

    // Verify tokens appear in registration order
    for i in Range(0, n) do
      try
        ph.assert_true(tokens(i)? == flushed_chunk_tokens(i)?,
          "Token order mismatch at position " + i.string())
      end
    end

// ---------------------------------------------------------------------------
// Permutation generator for property tests
// ---------------------------------------------------------------------------

primitive \nodoc\ _PermutationGenerator
  """
  Generate a random permutation of 0..n-1 using Fisher-Yates shuffle.
  """
  fun apply(n: USize): Generator[Array[USize] val] =>
    // Generate n random USize values to use as shuffle entropy
    Generators.array_of[USize](Generators.usize(0, USize.max_value())
      where min = n, max = n)
      .map[Array[USize] val](
        {(entropy: Array[USize] ref): Array[USize] val =>
          // Create identity permutation
          let perm = Array[USize](n)
          for i in Range(0, n) do
            perm.push(i)
          end
          // Fisher-Yates shuffle using entropy values
          var i: USize = n - 1
          while i > 0 do
            try
              let j = entropy(i)? % (i + 1)
              let tmp = perm(i)?
              perm(i)? = perm(j)?
              perm(j)? = tmp
            end
            i = i - 1
          end
          // Copy ref array to val via iso intermediate
          var result = recover iso Array[USize](n) end
          var k: USize = 0
          while k < n do
            try result.push(perm(k)?) end
            k = k + 1
          end
          consume result
        })
