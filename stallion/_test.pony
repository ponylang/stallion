use "pony_test"
use "pony_check"
use lori = "lori"
actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
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

    // Response builder tests
    test(Property1UnitTest[_ResponseInput](
      _PropertyBuilderMatchesSerializer))
    test(_TestResponseBuilderKnownGood)
    test(_TestRespond)
    test(_TestRespondIgnoredAfterFirst)
    test(_TestStartChunkedSuccess)
    test(_TestStartChunkedHTTP10)
    test(_TestStartChunkedAlreadyResponded)
    test(_TestStartChunkedAlreadyStreaming)

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
    test(_TestMaxRequestsPerConnection)
    test(_TestServerTimerFires)
    test(_TestServerTimerCancelled)

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

    // Response queue token tests
    test(Property1UnitTest[Array[USize] val](
      _PropertyQueueTokenOrder))
    test(_TestQueueTokenImmediateFlush)
    test(_TestQueueTokenBufferedFlush)
    test(_TestQueueTokenNoneForInternalSends)
    test(_TestQueueTokenThrottle)
    test(_TestQueueTokenClose)

    // Pipelining and streaming integration tests
    test(_TestPipelineCorrectness)
    test(_TestPipelineConnectionClose)
    test(_TestStreamingResponse)
    test(_TestMaxPendingOverflow)
    test(_TestHTTP10ChunkedRejection)
    test(_TestChunkSentCallback)

    // URI parsing integration tests
    test(_TestURIParsing)
    test(_TestConnectURIParsing)

    // Request body integration tests
    test(_TestBody)
    test(_TestServerNoBody)
    test(_TestServerContentLengthZero)
    test(_TestPipelinedBodies)

    // Cookie validator tests
    test(Property1UnitTest[String val](
      _PropertyValidCookieNameAccepted))
    test(Property1UnitTest[String val](
      _PropertyInvalidCookieNameRejected))
    test(Property1UnitTest[(String val, Bool)](
      _PropertyCookieNameBoundary))
    test(Property1UnitTest[String val](
      _PropertyValidCookieValueAccepted))
    test(Property1UnitTest[String val](
      _PropertyInvalidCookieValueRejected))
    test(Property1UnitTest[(String val, Bool)](
      _PropertyCookieValueBoundary))

    // Attribute value validator tests
    test(Property1UnitTest[String val](
      _PropertyValidAttrValueAccepted))
    test(Property1UnitTest[String val](
      _PropertyInvalidAttrValueRejected))
    test(Property1UnitTest[(String val, Bool)](
      _PropertyAttrValueBoundary))

    // HTTP date tests
    test(_TestHTTPDateKnownGood)
    test(Property1UnitTest[I64](_PropertyHTTPDateFormat))

    // Cookie parsing tests
    test(_TestParseCookieKnownGood)
    test(Property1UnitTest[Array[(String val, String val)] ref](
      _PropertyCookieParseRoundtrip))
    test(Property1UnitTest[String val](
      _PropertyCookieParseRobustness))

    // Set-Cookie builder tests
    test(_TestSetCookieKnownGood)
    test(_TestSetCookieErrors)
    test(Property1UnitTest[(String val, String val)](
      _PropertySetCookieValidBuild))
    test(Property1UnitTest[String val](
      _PropertySetCookieInvalidNameErrors))
    test(Property1UnitTest[String val](
      _PropertySetCookieInvalidValueErrors))

    // Cookie integration test
    test(_TestServerCookieParsing)

    // Content negotiation tests
    test(Property1UnitTest[String val](
      _PropertyNegotiateRobustness))
    test(Property1UnitTest[USize](
      _PropertyNegotiateResultFromSupported))
    test(Property1UnitTest[USize](
      _PropertyNegotiateQZeroExcludes))
    test(Property1UnitTest[USize](
      _PropertyNegotiateServerPreference))
    test(Property1UnitTest[String val](
      _PropertyNegotiateQualityBounds))
    test(_TestNegotiateKnownGood)
    test(_TestAcceptParserKnownGood)

    // SSL integration tests
    test(_TestSSLHelloWorld)
    test(_TestSSLKeepAlive)
    test(_TestSSLConnectionClose)
    test(_TestSSLParseError)
    test(_TestSSLStreamingResponse)
    test(_TestSSLStartFailure)
