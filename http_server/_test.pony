use "pony_test"
use "pony_check"
use lori = "lori"
use uri = "./uri"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    // URI subpackage tests
    uri.Main.make().tests(test)

    // Method tests
    test(Property1UnitTest[String val](_PropertyValidMethodParsesCorrectly))
    test(Property1UnitTest[String val](_PropertyInvalidMethodReturnsNone))
    test(Property1UnitTest[(String val, Bool)](
      _PropertyMethodParseBoundary))

    // Headers tests
    test(Property1UnitTest[(String val, String val)](
      _PropertyHeadersCaseInsensitive))
    test(Property1UnitTest[(String val, String val, String val)](
      _PropertyHeadersSetReplaces))
    test(Property1UnitTest[(String val, String val, String val)](
      _PropertyHeadersAddPreserves))

    // Response serializer tests
    test(Property1UnitTest[_ResponseInput](
      _PropertyResponseWireFormat))
    test(_TestResponseSerializerKnownGood)

    // Parser property-based tests
    test(Property1UnitTest[(String val, String val)](
      _PropertyValidRequestLineParsesCorrectly))
    test(Property1UnitTest[String val](
      _PropertyInvalidMethodRejected))
    test(Property1UnitTest[Array[(String val, String val)] ref](
      _PropertyHeadersRoundtrip))
    test(Property1UnitTest[USize](
      _PropertyFixedBodyDelivered))
    test(Property1UnitTest[Array[USize] ref](
      _PropertyChunkedBodyDelivered))
    test(Property1UnitTest[(String val, Bool)](
      _PropertyRequestLineBoundary))

    // Parser example-based tests
    test(_TestParserKnownGoodRequests)
    test(_TestIncrementalByteByByte)
    test(_TestPipelining)
    test(_TestPipeliningWithBody)
    test(_TestPipeliningChunked)
    test(_TestSizeLimitRequestLine)
    test(_TestSizeLimitHeaders)
    test(_TestSizeLimitBody)
    test(_TestInvalidContentLength)
    test(_TestInvalidChunkSize)
    test(_TestMissingCRLFAfterChunk)
    test(_TestChunkedWithTrailers)
    test(_TestHTTP10Version)
    test(_TestInvalidVersion)
    test(_TestNoBody)
    test(_TestContentLengthZero)
    test(_TestContentLengthAndChunked)
    test(_TestDuplicateContentLength)
    test(_TestInvalidURI)
    test(_TestDataAfterError)

    // Server integration tests
    test(_TestServerHelloWorld)
    test(_TestServerParseError)
    test(_TestKeepAlive)
    test(_TestConnectionClose)
    test(_TestHTTP10Close)
    test(_TestErrorResponse413)
    test(_TestErrorResponse431)
    test(_TestErrorResponse505)
    test(_TestIdleTimeout)
    test(_TestServerNotifyListening)

    // Keep-alive decision property test
    test(Property1UnitTest[(Version, (String val | None))](
      _PropertyKeepAliveDecision))

    // Chunked encoder tests
    test(Property1UnitTest[Array[U8] val](
      _PropertyChunkedEncoderFormat))
    test(_TestChunkedEncoderKnownInputs)

    // Response queue tests
    test(Property1UnitTest[Array[USize] val](
      _PropertyQueueInOrderDelivery))
    test(Property1UnitTest[(USize, Array[USize] val)](
      _PropertyQueueMixedResponses))
    test(_TestQueueReverseOrder)
    test(_TestQueueKeepAliveFalseStopsFlush)
    test(_TestQueueStreamingHead)
    test(_TestQueueStreamingNonHead)
    test(_TestQueueThrottleUnthrottle)
    test(_TestQueueCloseOnFlushData)

    // Pipelining and streaming integration tests
    test(_TestPipelineCorrectness)
    test(_TestPipelineConnectionClose)
    test(_TestStreamingResponse)
    test(_TestMaxPendingOverflow)
    test(_TestHTTP10ChunkedRejection)

    // URI parsing integration tests
    test(_TestURIParsing)
    test(_TestConnectURIParsing)
