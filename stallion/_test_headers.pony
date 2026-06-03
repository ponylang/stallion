use "pony_check"
use "pony_test"

class \nodoc\ iso _PropertyHeadersCaseInsensitive
  is Property1[(String val, String val)]
  """
  Adding a header and retrieving it with a different case variant returns
  the same value.
  """
  fun name(): String => "headers/case_insensitive"

  fun gen(): Generator[(String val, String val)] =>
    Generators.zip2[String val, String val](
      Generators.ascii_letters(1, 20),
      Generators.ascii_printable(1, 50))

  fun ref property(
    arg1: (String val, String val),
    ph: PropertyHelper)
  =>
    (let header_name, let value) = arg1
    let headers = Headers
    headers.add(header_name, value)

    // Retrieve with different case variants
    ph.assert_eq[String val](value, _get_or_empty(headers, header_name.upper()))
    ph.assert_eq[String val](value, _get_or_empty(headers, header_name.lower()))

  fun _get_or_empty(headers: Headers box, header_name: String): String val =>
    match headers.get(header_name)
    | let v: String val => v
    else
      ""
    end

class \nodoc\ iso _PropertyHeadersSetReplaces
  is Property1[(String val, String val, String val)]
  """
  Calling `set()` twice for the same name keeps only the second value.
  """
  fun name(): String => "headers/set_replaces"

  fun gen(): Generator[(String val, String val, String val)] =>
    Generators.zip3[String val, String val, String val](
      Generators.ascii_letters(1, 20),
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(1, 50))

  fun ref property(
    arg1: (String val, String val, String val),
    ph: PropertyHelper)
  =>
    (let header_name, let v1, let v2) = arg1
    let headers = Headers
    headers.set(header_name, v1)
    headers.set(header_name, v2)

    ph.assert_eq[USize](1, headers.size())
    ph.assert_eq[String val](v2, _get_or_empty(headers, header_name))

  fun _get_or_empty(headers: Headers box, header_name: String): String val =>
    match headers.get(header_name)
    | let v: String val => v
    else
      ""
    end

class \nodoc\ iso _PropertyHeadersAddPreserves
  is Property1[(String val, String val, String val)]
  """
  Calling `add()` twice for the same name keeps both values. `size()` reflects
  both entries, and for a non-list-valued field `get()` returns the first.
  (List-valued fields combine instead — see `_PropertyGetCombinesListField`.)
  """
  fun name(): String => "headers/add_preserves"

  fun gen(): Generator[(String val, String val, String val)] =>
    // Exclude list-valued names: for those, get() combines rather than
    // returning the first value, so the assertion below would not hold.
    Generators.zip3[String val, String val, String val](
      Generators.ascii_letters(1, 20)
        .filter(
          {(s: String val): (String val, Bool) =>
            (s, not _ListValuedHeaders(s.lower()))}),
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(1, 50))

  fun ref property(
    arg1: (String val, String val, String val),
    ph: PropertyHelper)
  =>
    (let header_name, let v1, let v2) = arg1
    let headers = Headers
    headers.add(header_name, v1)
    headers.add(header_name, v2)

    ph.assert_eq[USize](2, headers.size())
    // get() returns the first value added
    ph.assert_eq[String val](v1, _get_or_empty(headers, header_name))

  fun _get_or_empty(headers: Headers box, header_name: String): String val =>
    match headers.get(header_name)
    | let v: String val => v
    else
      ""
    end

class \nodoc\ iso _PropertyGetCombinesListField
  is Property1[(String val, Array[String val] ref)]
  """
  For a list-valued field, `get()` returns the values of all lines with that
  name combined into one value, joined by commas in the order they appeared
  (RFC 9110 §5.3). A non-matching header is interleaved between the entries so
  the test exercises `get()`'s name-filtering, not just a flat join.
  """
  fun name(): String => "headers/get_combines_list_field"

  fun gen(): Generator[(String val, Array[String val] ref)] =>
    let name_gen = Generators.one_of[String val](
      [as String val:
        "connection"; "transfer-encoding"; "te"; "trailer"; "upgrade"
        "via"; "accept"; "accept-charset"; "accept-encoding"
        "accept-language"; "cache-control"; "content-encoding"
        "content-language"; "if-match"; "if-none-match"; "expect"])
    // Comma-free values so the expected join is unambiguous.
    let values_gen = Generators.array_of[String val](
      Generators.ascii_letters(1, 15), 1, 5)
    Generators.zip2[String val, Array[String val] ref](name_gen, values_gen)

  fun ref property(
    arg1: (String val, Array[String val] ref),
    ph: PropertyHelper)
  =>
    (let field, let values) = arg1
    let headers = Headers
    for v in values.values() do
      headers.add(field, v)
      headers.add("x-noise", "n")
    end
    let expected: String val = ",".join(values.values())
    ph.assert_eq[String val](expected, _get_or_empty(headers, field))

  fun _get_or_empty(headers: Headers box, header_name: String): String val =>
    match headers.get(header_name)
    | let v: String val => v
    else
      ""
    end

class \nodoc\ iso _PropertyGetFirstValueNonListField
  is Property1[(String val, Array[String val] ref)]
  """
  For a field that is not list-valued, `get()` returns the first value added,
  regardless of how many lines share the name. Names are prefixed with `x-`,
  which no allowlist member uses, so they are guaranteed non-list.
  """
  fun name(): String => "headers/get_first_value_non_list"

  fun gen(): Generator[(String val, Array[String val] ref)] =>
    let name_gen = Generators.ascii_letters(1, 15)
      .map[String val]({(s: String val): String val => "x-" + s})
    let values_gen = Generators.array_of[String val](
      Generators.ascii_letters(1, 15), 1, 5)
    Generators.zip2[String val, Array[String val] ref](name_gen, values_gen)

  fun ref property(
    arg1: (String val, Array[String val] ref),
    ph: PropertyHelper)
  =>
    (let field, let values) = arg1
    let headers = Headers
    for v in values.values() do
      headers.add(field, v)
    end
    let first: String val = try values(0)? else "" end
    ph.assert_eq[String val](first, _get_or_empty(headers, field))

  fun _get_or_empty(headers: Headers box, header_name: String): String val =>
    match headers.get(header_name)
    | let v: String val => v
    else
      ""
    end

class \nodoc\ iso _TestHeadersListNoMatchNone is UnitTest
  """
  `get()` returns `None` when no header with the name exists — for both the
  list-valued branch and the first-value branch.
  """
  fun name(): String => "headers/no_match_none"

  fun apply(h: TestHelper) =>
    let headers = Headers
    h.assert_true(headers.get("connection") is None,
      "list field with no entries returns None")
    h.assert_true(headers.get("x-custom") is None,
      "non-list field with no entries returns None")
    headers.add("host", "example.com")
    h.assert_true(headers.get("connection") is None,
      "list field still None when only other headers are present")

class \nodoc\ iso _TestHeadersDeniedNotCombined is UnitTest
  """
  Deny-listed fields keep first-value semantics and are never combined.
  Combining these would corrupt the message (e.g. the comma inside
  Set-Cookie's Expires date).
  """
  fun name(): String => "headers/denied_not_combined"

  fun apply(h: TestHelper) =>
    _check(h, "Set-Cookie",
      "id=1; Expires=Sun, 06 Nov 1994 08:49:37 GMT", "id=2")
    _check(h, "Date", "Mon, 01 Jan 2024 00:00:00 GMT",
      "Tue, 02 Jan 2024 00:00:00 GMT")
    _check(h, "Cookie", "a=1", "b=2")
    _check(h, "X-Custom", "first", "second")

  fun _check(
    h: TestHelper,
    field: String,
    first: String val,
    second: String val)
  =>
    let headers = Headers
    headers.add(field, first)
    headers.add(field, second)
    match headers.get(field)
    | let v: String val =>
      h.assert_eq[String val](first, v,
        field + " must return the first value, not a combined one")
    | None =>
      h.fail(field + " unexpectedly returned None")
    end

class \nodoc\ iso _TestHeadersCombineSeparatorEdges is UnitTest
  """
  The combine loop places a comma between entries, never around them, and
  preserves insertion order. A single entry returns its value unchanged; an
  empty leading value still gets a separator before the next entry.
  """
  fun name(): String => "headers/combine_separator_edges"

  fun apply(h: TestHelper) =>
    // Three entries: comma between, not around; order preserved.
    let h3 = Headers
    h3.add("Via", "1.1 a")
    h3.add("Via", "1.0 b")
    h3.add("Via", "2 c")
    h.assert_eq[String val]("1.1 a,1.0 b,2 c", _get(h3, "via"))
    // Empty leading value: separator still emitted between entries.
    let he = Headers
    he.add("Connection", "")
    he.add("Connection", "close")
    h.assert_eq[String val](",close", _get(he, "connection"))
    // Single entry via set(): no separator, value unchanged.
    let hs = Headers
    hs.set("Connection", "keep-alive")
    h.assert_eq[String val]("keep-alive", _get(hs, "connection"))

  fun _get(headers: Headers box, field: String): String val =>
    match headers.get(field)
    | let v: String val => v
    else
      ""
    end

class \nodoc\ iso _TestKeepAliveMultiLineViaGet is UnitTest
  """
  End-to-end regression for #105: repeated `Connection` lines are combined by
  `Headers.get` and honored by `_KeepAliveDecision`. A `close` on a later line
  closes; `keep-alive` across lines keeps alive. Before the fix, `get()`
  returned only the first line and the connection stayed open.
  """
  fun name(): String => "headers/keep_alive_multi_line"

  fun apply(h: TestHelper) =>
    let hc = Headers
    hc.add("Connection", "keep-alive")
    hc.add("Connection", "close")
    h.assert_false(_KeepAliveDecision(HTTP11, hc.get("connection")),
      "close on a later Connection line must close")

    let hk = Headers
    hk.add("Connection", "keep-alive")
    hk.add("Connection", "Upgrade")
    h.assert_true(_KeepAliveDecision(HTTP10, hk.get("connection")),
      "keep-alive across Connection lines must keep alive on HTTP/1.0")

class \nodoc\ iso _TestListValuedHeadersAllowlist is UnitTest
  """
  Every allowlisted field is recognized as list-valued; non-list names, the
  empty string, substring near-misses, and uppercased names are not. The
  uppercase rows document that the caller must lowercase before calling.
  """
  fun name(): String => "headers/list_valued_allowlist"

  fun apply(h: TestHelper) =>
    let allow: Array[String val] =
      [ "connection"; "transfer-encoding"; "te"; "trailer"; "upgrade"
        "via"; "accept"; "accept-charset"; "accept-encoding"
        "accept-language"; "cache-control"; "content-encoding"
        "content-language"; "if-match"; "if-none-match"; "expect" ]
    for field in allow.values() do
      h.assert_true(_ListValuedHeaders(field),
        field + " should be a list-valued field")
    end

    let not_list: Array[String val] =
      [ "x-custom"; "foo"; ""; "connectionx"; "xconnection"; "x-accept"
        "accept-foo"; "te2"; "upgraded"; "transfer-encodings" ]
    for field in not_list.values() do
      h.assert_false(_ListValuedHeaders(field),
        field + " should not be a list-valued field")
    end

    h.assert_false(_ListValuedHeaders("Connection"),
      "uppercase name must not match (caller lowercases)")
    h.assert_false(_ListValuedHeaders("ACCEPT"),
      "uppercase name must not match (caller lowercases)")

class \nodoc\ iso _TestListValuedHeadersDenyDisjoint is UnitTest
  """
  Every header the `_ListValuedHeaders` docstring documents as deliberately
  NOT a list must be absent from the allowlist. Guards against a future edit
  that adds one of these to the allowlist, which would corrupt the field
  (RFC 9110 §5.3). The deny list is duplicated here intentionally so the test
  owns its inputs.
  """
  fun name(): String => "headers/list_valued_deny_disjoint"

  fun apply(h: TestHelper) =>
    let deny: Array[String val] =
      [ "set-cookie"; "cookie"; "www-authenticate"; "proxy-authenticate"
        "date"; "expires"; "last-modified"; "if-modified-since"
        "if-unmodified-since"; "content-length"; "host"; "authorization"
        "proxy-authorization" ]
    for field in deny.values() do
      h.assert_false(_ListValuedHeaders(field),
        field + " is deny-listed and must never be combined")
    end
