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

    // OWS tests
    test(_TestOWS)

    // Token tests
    test(_TestToken)

    // Field value tests
    test(_TestFieldValue)

    // Host value tests
    test(_TestHostValue)
    test(_TestHostAuthorityMatch)

    // Request conformance corpus (table-driven)
    test(_TestRequestConformance)
    test(_TestRequestParity)
    test(_TestBareCRLFInjection)
    test(_TestParseSplitInvariance)
    test(_TestCompletionPoints)
    test(_TestSizeLimitChunkHeader)
    test(_TestSizeLimitHeadersCumulative)

    // Quoted-split tokenizer tests
    test(_TestQuotedSplit)

    // Headers tests
    test(Property1UnitTest[(String val, String val)](
      _PropertyHeadersCaseInsensitive))
    test(Property1UnitTest[(String val, String val, String val)](
      _PropertyHeadersSetReplaces))
    test(Property1UnitTest[(String val, String val, String val)](
      _PropertyHeadersAddPreserves))
    test(Property1UnitTest[(String val, Array[String val] ref)](
      _PropertyGetCombinesListField))
    test(Property1UnitTest[(String val, Array[String val] ref)](
      _PropertyGetFirstValueNonListField))
    test(_TestHeadersListNoMatchNone)
    test(_TestHeadersDeniedNotCombined)
    test(_TestHeadersCombineSeparatorEdges)
    test(_TestKeepAliveMultiLineViaGet)
    test(_TestListValuedHeadersAllowlist)
    test(_TestListValuedHeadersDenyDisjoint)

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
    test(_TestSendChunkAfterClose)
    test(_TestStartChunkedConnectionClosed)
    test(_TestStartChunkedClosedAfterResponded)
    test(_TestStartChunkedClosedBeatsHTTP10)
    test(_TestStartChunkedClosedLeavesState)
    test(_TestStartChunkedClosedMidCall)
    test(_TestSendChunkClosedMidCall)

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
    test(_TestTransferEncodingUnknownNoBody)
    test(_TestTransferEncodingUnknownWithChunkedBody)
    test(_TestTransferEncodingGzipChunked)
    test(_TestTransferEncodingChunkedNotFinal)
    test(_TestTransferEncodingDuplicateChunked)
    test(_TestTransferEncodingEmpty)
    test(_TestTransferEncodingUppercase)
    test(_TestTransferEncodingWithParams)
    test(_TestTransferEncodingQuotedComma)
    test(_TestTransferEncodingUnterminatedQuote)
    test(_TestTransferEncodingTrailingComma)
    test(_TestTransferEncodingMultiLine)
    test(_TestTransferEncodingEvaluate)
    test(_TestDuplicateContentLength)
    test(_TestInvalidURI)
    test(_TestDataAfterError)

    // Pure server tests (fake TCPBackend, no real sockets)
    test(_TestPureHelloWorld)
    test(_TestPureParseError)
    test(_TestPureError413)
    test(_TestPureError431)
    test(_TestPureError505)
    test(_TestPureKeepAlive)
    test(_TestPureConnectionClose)
    test(_TestPureHTTP10Close)
    test(_TestPureClosingDropsData)
    test(_TestPureOnClosedOrdering)
    test(_TestPureMaxRequestsPerConnection)
    test(_TestPureOnThrottledBuffers)
    test(_TestPureOnUnthrottledFlushes)
    test(_TestPureCloseUnderBackpressure)
    test(_TestPurePipelineCorrectness)
    test(_TestPurePipelineConnectionClose)
    test(_TestPureStreamingResponse)
    test(_TestPureMaxPendingOverflow)
    test(_TestPureHTTP10ChunkedRejection)
    test(_TestPureChunkSentCallback)
    test(_TestPureChunkSentBeforeClose)
    test(_TestPureChunksSentMultipleBeforeClose)
    test(_TestPureChunkSentPipelinedNonHead)
    test(_TestPureURIParsing)
    test(_TestPureConnectURIParsing)
    test(_TestPureBody)
    test(_TestPureNoBody)
    test(_TestPureContentLengthZero)
    test(_TestPurePipelinedBodies)
    test(_TestPureCookieParsing)
    test(_TestPureMissingHost)
    test(_TestPureDuplicateHost)
    test(_TestPureDuplicateHostHTTP10)
    test(_TestPureDuplicateHostWithBody)
    test(_TestPureInvalidHostValue)
    test(_TestPureHostPortOutOfRange)
    test(_TestPureEmptyHostValue)
    test(_TestPureIPv6HostValue)
    test(_TestPureConnectOk)
    test(_TestPureUnknownMethod)
    test(_TestPureAbsoluteFormHostMatch)
    test(_TestPureAbsoluteFormHostMismatch)
    test(_TestPureAbsoluteFormDefaultPort)
    test(_TestPureAbsoluteFormDefaultPortHTTPS)
    test(_TestPureAbsoluteFormHostCaseInsensitive)
    test(_TestPureAbsoluteFormPortMatch)
    test(_TestPureAbsoluteFormPortMismatch)
    test(_TestPureConnectHostMismatch)
    test(_TestPureAbsoluteFormUserinfo)
    test(_TestPureAbsoluteFormMultipleAt)
    test(_TestPureAbsoluteFormUserinfoNoHost)
    test(_TestPureConnectUserinfo)
    test(_TestPureAbsoluteFormEmptyHost)
    test(_TestPureConnectMissingPort)
    test(_TestPureConnectEmptyPort)

    // Server integration tests
    test(_TestServerHelloWorld)
    test(_TestKeepAlive)
    test(_TestIdleTimeout)
    test(_TestIdleTimeoutClosesStalledConnection)
    test(_TestServerTimerFires)
    test(_TestServerTimerCancelled)

    // Keep-alive decision tests
    test(Property1UnitTest[(Version, (String val | None))](
      _PropertyKeepAliveDecision))
    test(Property1UnitTest[(String val, Array[String val] ref, USize, Version)](
      _PropertyKeepAliveCloseAlwaysWins))
    test(_TestKeepAliveMultiToken)

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

    // Mid-flush re-throttle tests (issue #132)
    test(_TestQueueRethrottleMidFlushResumes)
    test(_TestQueueFinishWhileThrottledKeepsData)
    test(_TestQueueRethrottleMidFlushNewHead)
    test(_TestQueueRethrottleOnLastChunk)
    test(_TestQueueCloseDuringRethrottle)
    test(Property1UnitTest[(USize, USize)](
      _PropertyQueueRethrottleDelivery))

    // Response queue token tests
    test(Property1UnitTest[Array[USize] val](
      _PropertyQueueTokenOrder))
    test(_TestQueueTokenImmediateFlush)
    test(_TestQueueTokenBufferedFlush)
    test(_TestQueueTokenNoneForInternalSends)
    test(_TestQueueTokenThrottle)
    test(_TestQueueTokenClose)
    test(_TestQueueHasEntry)
    test(_TestQueueCloseDiscardsEntries)

    test(_TestTimerFiresWhileClosing)

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
