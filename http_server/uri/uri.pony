"""
# URI Parsing (RFC 3986)

This package parses URI-references into structured components per RFC 3986.

## Entry Points

Use `ParseURI` for standard URI-references (absolute URIs and relative
references — covers origin-form, absolute-form, and asterisk-form HTTP
request-targets):

```pony
match ParseURI("/index.html?page=1")
| let u: URI val => // u.path, u.query, etc.
| let e: URIParseError val => // handle error
end
```

Use `ParseURIAuthority` for HTTP CONNECT authority-form targets
(`host:port` without scheme or `//`):

```pony
match ParseURIAuthority("example.com:443")
| let a: URIAuthority val => // a.host, a.port
| let e: URIParseError val => // handle error
end
```

For query parameter access, `URI.query_params()` is the simplest path —
it returns a `QueryParams` collection with `get()`, `get_all()`, and
`contains()` methods for key-based lookup. Use `ParseQueryParameters`
directly on the `query` field when you need to distinguish "no query"
from "invalid percent-encoding." Use `PercentDecode`/`PercentEncode`
for encoding operations, and `PathSegments` for decoded path segment
access.
"""

class val URI is (Stringable & Equatable[URI])
  """
  A parsed RFC 3986 URI-reference.

  Components are stored in their percent-encoded form as they appeared in
  the input. Delimiter characters (`:` after scheme, `//` before authority,
  `?` before query, `#` before fragment) are stripped — use `string()` to
  reconstruct the full URI with delimiters.

  `string()` reconstruction follows RFC 3986 section 5.3. Components that
  are `None` are omitted entirely (no delimiter). A component that is an
  empty `String` (present but empty) includes its delimiter — e.g.,
  `query` of `""` produces a trailing `?` with no value. This distinction
  allows faithful reconstruction of inputs like `http://example.com/path?`
  (empty query present, `query = ""`) vs. `http://example.com/path`
  (no query at all, `query = None`).

  Equality is structural: two URIs are equal when all their stored
  (percent-encoded) components are equal. No normalization is applied
  before comparison.
  """
  let scheme: (String | None)
  let authority: (URIAuthority | None)
  let path: String
  let query: (String | None)
  let fragment: (String | None)

  new val create(
    scheme': (String | None),
    authority': (URIAuthority | None),
    path': String,
    query': (String | None),
    fragment': (String | None))
  =>
    scheme = scheme'
    authority = authority'
    path = path'
    query = query'
    fragment = fragment'

  fun string(): String iso^ =>
    // RFC 3986 section 5.3
    let out = recover iso String end
    match scheme
    | let s: String => out.append(s); out.push(':')
    end
    match authority
    | let a: URIAuthority =>
      out.append("//")
      out.append(a.string())
    end
    out.append(path)
    match query
    | let q: String => out.push('?'); out.append(q)
    end
    match fragment
    | let f: String => out.push('#'); out.append(f)
    end
    out

  fun query_params(): (QueryParams val | None) =>
    """
    Parse the query string into a `QueryParams` collection.

    Returns the parsed parameters if the query is present and decodes
    successfully, or `None` if no query is present or if the query
    contains invalid percent-encoding. For fine-grained error handling
    (distinguishing "no query" from "decode failure"), use
    `ParseQueryParameters` directly on the `query` field.
    """
    match query
    | let q: String val =>
      match ParseQueryParameters(q)
      | let params: QueryParams val => params
      | let _: InvalidPercentEncoding => None
      end
    | None => None
    end

  fun eq(that: URI box): Bool =>
    let scheme_eq =
      match (scheme, that.scheme)
      | (None, None) => true
      | (let a: String, let b: String) => a == b
      else
        false
      end
    let authority_eq =
      match (authority, that.authority)
      | (None, None) => true
      | (let a: URIAuthority, let b: URIAuthority) => a == b
      else
        false
      end
    let query_eq =
      match (query, that.query)
      | (None, None) => true
      | (let a: String, let b: String) => a == b
      else
        false
      end
    let fragment_eq =
      match (fragment, that.fragment)
      | (None, None) => true
      | (let a: String, let b: String) => a == b
      else
        false
      end
    scheme_eq and authority_eq and (path == that.path)
      and query_eq and fragment_eq
