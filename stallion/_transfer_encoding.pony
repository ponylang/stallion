primitive _ChunkedFraming
  """
  The Transfer-Encoding resolves to `chunked` framing.

  Sentinel returned by `_TransferEncoding.evaluate` to signal that the
  request body should be parsed as chunked transfer encoding.
  """

primitive _TransferEncoding
  """
  RFC 9112 §6.1/§6.3 Transfer-Encoding handling.

  `Transfer-Encoding` is an ordered, comma-separated list of
  transfer-coding tokens. Stallion only understands `chunked`, so any
  other coding is unsupported. The token list is matched exactly
  (case-insensitively) — never by substring.
  """

  fun append_codings(value: String val, tokens: Array[String] ref) =>
    """
    Tokenize one Transfer-Encoding field value and append each normalized
    coding name to `tokens`.

    Each token is normalized by removing any `;`-delimited parameters,
    stripping surrounding optional whitespace, and lowercasing. Empty
    list elements are ignored per RFC 9110 §5.6.1. Tokens are appended in
    order so a caller can determine which coding is final across multiple
    Transfer-Encoding header lines.
    """
    let parts: Array[String] = value.split(",")
    for raw in parts.values() do
      let coding: String = _normalize(raw)
      if coding.size() > 0 then
        tokens.push(coding)
      end
    end

  fun _normalize(raw: String box): String iso^ =>
    """
    Strip parameters and OWS from a single coding, then lowercase it.

    Stallion combines repeated list-valued header lines in three places,
    each for its own reason: this parser path (Transfer-Encoding must be
    resolved during parsing, before the body, so it accumulates per line and
    cannot wait for a complete `Headers`), `ContentNegotiation.from_request`
    (Accept), and `Headers.get` (everything in `_ListValuedHeaders`,
    including Connection). Unifying them is tracked in issue #117; until
    then, this normalizer stays local. `_KeepAliveDecision._normalize` is the
    near-identical sibling (it omits the `;`-parameter cut, as connection
    options have none).
    """
    let cut_at: ISize = try raw.find(";")? else raw.size().isize() end
    let coding: String ref = raw.substring(0, cut_at)
    coding.strip(" \t") // RFC 9110 OWS is only SP and HTAB
    coding.lower()

  fun evaluate(tokens: Array[String] box)
    : (_ChunkedFraming | UnsupportedTransferEncoding | InvalidTransferEncoding)
  =>
    """
    Decide how to handle the combined, ordered list of transfer codings.

    Only `chunked`, as the sole/final coding, is supported. Any other
    coding is unsupported (501). A list that cannot frame the message —
    empty, `chunked` repeated, or `chunked` not final — is invalid (400).
    """
    if tokens.size() == 0 then
      // Header present but no usable codings (empty or all-empty value).
      return InvalidTransferEncoding
    end

    // Single pass: count `chunked` and remember whether the final coding is
    // `chunked` (the loop runs at least once, so last_is_chunked is set).
    var chunked_count: USize = 0
    var last_is_chunked = false
    for coding in tokens.values() do
      last_is_chunked = coding == "chunked"
      if last_is_chunked then
        chunked_count = chunked_count + 1
      end
    end

    if chunked_count > 1 then
      // `chunked` must not be applied more than once.
      return InvalidTransferEncoding
    end

    if last_is_chunked then
      if tokens.size() == 1 then
        _ChunkedFraming
      else
        // `chunked` is final, but other codings we don't implement precede it.
        UnsupportedTransferEncoding
      end
    elseif chunked_count == 1 then
      // `chunked` present but not the final coding: length undeterminable.
      InvalidTransferEncoding
    else
      // No `chunked` at all: unknown coding(s) we don't implement.
      UnsupportedTransferEncoding
    end
