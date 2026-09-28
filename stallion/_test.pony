use "pony_test"
use "net"
actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    // Method tests
    test.property(_PropertyValidMethodParsesCorrectly)
    test.property(_PropertyInvalidMethodReturnsNone)
    test.property(_PropertyMethodParseBoundary)

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
    test.property(_PropertyHeadersCaseInsensitive)
    test.property(_PropertyHeadersSetReplaces)
    test.property(_PropertyHeadersAddPreserves)
    test.property(_PropertyGetCombinesListField)
    test.property(_PropertyGetFirstValueNonListField)
    test(_TestHeadersListNoMatchNone)
    test(_TestHeadersDeniedNotCombined)
    test(_TestHeadersCombineSeparatorEdges)
    test(_TestKeepAliveMultiLineViaGet)
    test(_TestListValuedHeadersAllowlist)
    test(_TestListValuedHeadersDenyDisjoint)

    // Response serializer tests
    test.property(_PropertyResponseWireFormat)
    test(_TestResponseSerializerKnownGood)

    // Response builder tests
    test.property(_PropertyBuilderMatchesSerializer)
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
    test.property(_PropertyValidRequestLineParsesCorrectly)
    test.property(_PropertyInvalidMethodRejected)
    test.property(_PropertyHeadersRoundtrip)
    test.property(_PropertyFixedBodyDelivered)
    test.property(_PropertyChunkedBodyDelivered)
    test.property(_PropertyRequestLineBoundary)

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

    // Server integration tests
    test(_TestServerHelloWorld)
    test(_TestServerParseError)
    test(_TestServerMissingHost)
    test(_TestServerDuplicateHost)
    test(_TestServerInvalidHostValue)
    test(_TestServerHostPortOutOfRange)
    test(_TestServerEmptyHostValue)
    test(_TestServerIPv6HostValue)
    test(_TestServerConnectOk)
    test(_TestServerUnknownMethod)
    test(_TestServerDuplicateHostHTTP10)
    test(_TestServerDuplicateHostWithBody)
    test(_TestServerAbsoluteFormHostMatch)
    test(_TestServerAbsoluteFormHostMismatch)
    test(_TestServerAbsoluteFormDefaultPort)
    test(_TestServerAbsoluteFormDefaultPortHTTPS)
    test(_TestServerAbsoluteFormHostCaseInsensitive)
    test(_TestServerAbsoluteFormPortMatch)
    test(_TestServerAbsoluteFormPortMismatch)
    test(_TestServerConnectHostMismatch)
    test(_TestServerAbsoluteFormUserinfo)
    test(_TestServerAbsoluteFormMultipleAt)
    test(_TestServerAbsoluteFormUserinfoNoHost)
    test(_TestServerConnectUserinfo)
    test(_TestServerAbsoluteFormEmptyHost)
    test(_TestServerConnectMissingPort)
    test(_TestServerConnectEmptyPort)
    test(_TestKeepAlive)
    test(_TestConnectionClose)
    test(_TestHTTP10Close)
    test(_TestErrorResponse413)
    test(_TestErrorResponse431)
    test(_TestErrorResponse505)
    test(_TestIdleTimeout)
    test(_TestIdleTimeoutClosesStalledConnection)
    test(_TestMaxRequestsPerConnection)
    test(_TestServerTimerFires)
    test(_TestServerTimerCancelled)

    // Keep-alive decision tests
    test.property(_PropertyKeepAliveDecision)
    test.property(_PropertyKeepAliveCloseAlwaysWins)
    test(_TestKeepAliveMultiToken)

    // Chunked encoder tests
    test.property(_PropertyChunkedEncoderFormat)
    test(_TestChunkedEncoderKnownInputs)

    // Response queue tests
    test.property(_PropertyQueueInOrderDelivery)
    test.property(_PropertyQueueMixedResponses)
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
    test.property(_PropertyQueueRethrottleDelivery)

    // Response queue token tests
    test.property(_PropertyQueueTokenOrder)
    test(_TestQueueTokenImmediateFlush)
    test(_TestQueueTokenBufferedFlush)
    test(_TestQueueTokenNoneForInternalSends)
    test(_TestQueueTokenThrottle)
    test(_TestQueueTokenClose)
    test(_TestQueueHasEntry)
    test(_TestQueueCloseDiscardsEntries)

    // Pipelining and streaming integration tests
    test(_TestPipelineCorrectness)
    test(_TestPipelineConnectionClose)
    test(_TestStreamingResponse)
    test(_TestMaxPendingOverflow)
    test(_TestHTTP10ChunkedRejection)
    test(_TestChunkSentCallback)
    test(_TestChunkSentBeforeClose)
    test(_TestChunkSentMultipleBeforeClose)
    test(_TestOnClosedAfterResponse)
    test(_TestChunkSentPipelinedNonHead)
    test(_TestTimerFiresWhileClosing)


    // URI parsing integration tests
    test(_TestURIParsing)
    test(_TestConnectURIParsing)

    // Request body integration tests
    test(_TestBody)
    test(_TestServerNoBody)
    test(_TestServerContentLengthZero)
    test(_TestPipelinedBodies)

    // Cookie validator tests
    test.property(_PropertyValidCookieNameAccepted)
    test.property(_PropertyInvalidCookieNameRejected)
    test.property(_PropertyCookieNameBoundary)
    test.property(_PropertyValidCookieValueAccepted)
    test.property(_PropertyInvalidCookieValueRejected)
    test.property(_PropertyCookieValueBoundary)

    // Attribute value validator tests
    test.property(_PropertyValidAttrValueAccepted)
    test.property(_PropertyInvalidAttrValueRejected)
    test.property(_PropertyAttrValueBoundary)

    // HTTP date tests
    test(_TestHTTPDateKnownGood)
    test.property(_PropertyHTTPDateFormat)

    // Cookie parsing tests
    test(_TestParseCookieKnownGood)
    test.property(_PropertyCookieParseRoundtrip)
    test.property(_PropertyCookieParseRobustness)

    // Set-Cookie builder tests
    test(_TestSetCookieKnownGood)
    test(_TestSetCookieErrors)
    test.property(_PropertySetCookieValidBuild)
    test.property(_PropertySetCookieInvalidNameErrors)
    test.property(_PropertySetCookieInvalidValueErrors)

    // Cookie integration test
    test(_TestServerCookieParsing)

    // Content negotiation tests
    test.property(_PropertyNegotiateRobustness)
    test.property(_PropertyNegotiateResultFromSupported)
    test.property(_PropertyNegotiateQZeroExcludes)
    test.property(_PropertyNegotiateServerPreference)
    test.property(_PropertyNegotiateQualityBounds)
    test(_TestNegotiateKnownGood)
    test(_TestAcceptParserKnownGood)

    // SSL integration tests
    test(_TestSSLHelloWorld)
    test(_TestSSLKeepAlive)
    test(_TestSSLConnectionClose)
    test(_TestSSLParseError)
    test(_TestSSLStreamingResponse)
    test(_TestSSLStartFailure)
