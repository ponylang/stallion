primitive _ListValuedHeaders
  """
  Which HTTP header fields are comma-separated lists (RFC 9110 §5.6.1
  `#rule` fields).

  For these fields, multiple field lines with the same name are
  semantically equivalent to a single line whose value is the lines joined
  by commas in order (RFC 9110 §5.3). `Headers.get` relies on this to
  combine repeated lines into one value for the fields named here, and
  returns the first value for everything else.

  This is an allowlist, deliberately, so the failure mode is safe: a list
  field we forgot to register simply degrades to first-value behavior (the
  bug this guards against, for that one field) rather than corrupting a
  field that must never be combined. The set is the common request fields a
  server sees; it is meant to grow on demand, not to be exhaustive over all
  of HTTP (RFC 9110 §5.3 / IANA field registry).

  Fields deliberately NOT in the allowlist, and why — combining any of
  these would change the message's meaning, so they must keep first-value
  semantics. This list is captured here, next to the allowlist, so the
  reasoning that went into the allowlist is visible to whoever edits it; it
  is enforced by `_TestListValuedHeadersDenyDisjoint` (no denied field is
  also allowed) and by behavioral tests in `_test_headers.pony`:

  * `set-cookie` — RFC 9110 §5.3 explicitly forbids combining; values
    contain commas (the `Expires` date and attribute lists), and the field
    legitimately appears on multiple lines.
  * `cookie` — RFC 6265 §5.4: a single header whose pairs are
    `;`-separated, not a comma list.
  * `www-authenticate`, `proxy-authenticate` — `1#challenge`, but
    `auth-param` values legitimately contain commas, so a naive comma
    combine is unsafe.
  * `date`, `expires`, `last-modified`, `if-modified-since`,
    `if-unmodified-since` — singular; the IMF-fixdate value contains a comma
    (`Sun, 06 Nov 1994 08:49:37 GMT`).
  * `content-length` — singular; duplicate values are a framing error, not
    a list (rejected during parsing, not combined).
  * `host` — singular; exactly one is allowed (RFC 9112 §3.2).
  * `authorization`, `proxy-authorization` — single set of credentials;
    `auth-param` values may contain commas.
  """

  fun apply(name: String box): Bool =>
    """
    Whether `name` is a comma-separated list field. `name` must already be
    lowercased (header names are stored lowercase by `Headers`).
    """
    // This allowlist is duplicated in the tests: `_TestListValuedHeadersAllowlist`
    // asserts every entry, and `_PropertyGetCombinesListField`'s generator
    // draws from it. Keep all three in sync when adding or removing a field.
    match name
    | "connection" => true
    | "transfer-encoding" => true
    | "te" => true
    | "trailer" => true
    | "upgrade" => true
    | "via" => true
    | "accept" => true
    | "accept-charset" => true
    | "accept-encoding" => true
    | "accept-language" => true
    | "cache-control" => true
    | "content-encoding" => true
    | "content-language" => true
    | "if-match" => true
    | "if-none-match" => true
    | "expect" => true
    else
      false
    end
