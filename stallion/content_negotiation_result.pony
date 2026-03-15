// Result of content negotiation: either the best matching `MediaType` from
// the server's supported types, or `NoAcceptableType` if no match was found.
type ContentNegotiationResult is (MediaType val | NoAcceptableType)
