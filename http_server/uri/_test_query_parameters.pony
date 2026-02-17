use "pony_test"
use "pony_check"

class \nodoc\ iso _PropertyQueryParamsRoundtrip
  is Property1[Array[(String val, String val)] val]
  """
  Generated key-value pairs serialized as `k=v&k2=v2` parse back to
  matching pairs.
  """
  fun name(): String => "uri/query_parameters/roundtrip"

  fun gen(): Generator[Array[(String val, String val)] val] =>
    let key_gen = Generators.one_of[String val](
      ["key"; "name"; "q"; "page"; "id"; "foo"; "bar"])
    let val_gen = Generators.one_of[String val](
      ["value"; "1"; "hello"; ""; "test"; "42"; "abc"])
    let pair_gen = Generators.zip2[String val, String val](key_gen, val_gen)
    Generators.array_of[
      (String val, String val)](pair_gen where min = 0, max = 5)
      .map[Array[(String val, String val)] val](
        {(arr: Array[(String val, String val)] ref)
          : Array[(String val, String val)] val
        =>
          let out = recover iso
            Array[(String val, String val)](arr.size())
          end
          for pair in arr.values() do
            out.push(pair)
          end
          consume out
        })

  fun ref property(
    arg1: Array[(String val, String val)] val,
    ph: PropertyHelper)
  =>
    // Serialize
    let parts = Array[String val](arg1.size())
    for (k, v) in arg1.values() do
      parts.push(k + "=" + v)
    end
    let query = "&".join(parts.values())

    match ParseQueryParameters(consume query)
    | let parsed: Array[(String val, String val)] val =>
      ph.assert_eq[USize](arg1.size(), parsed.size(),
        "pair count mismatch")
      var i: USize = 0
      while i < arg1.size() do
        try
          (let ek, let ev) = arg1(i)?
          (let pk, let pv) = parsed(i)?
          ph.assert_eq[String val](ek, pk,
            "key mismatch at " + i.string())
          ph.assert_eq[String val](ev, pv,
            "value mismatch at " + i.string())
        end
        i = i + 1
      end
    | let err: InvalidPercentEncoding val =>
      ph.fail("roundtrip parse failed")
    end

class \nodoc\ iso _PropertyQueryParamsPlusDecodes is Property1[String val]
  """`+` in query values decodes as space."""
  fun name(): String => "uri/query_parameters/plus_decodes"

  fun gen(): Generator[String val] =>
    Generators.one_of[String val](
      ["hello+world"; "a+b+c"; "+"; "no+spaces+here"; "++"])

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    let query = "key=" + arg1
    match ParseQueryParameters(consume query)
    | let parsed: Array[(String val, String val)] val =>
      try
        (_, let v) = parsed(0)?
        let exp = String(arg1.size())
        for c in arg1.values() do
          if c == '+' then exp.push(' ') else exp.push(c) end
        end
        ph.assert_eq[String val](exp.clone(), v,
          "+ should decode as space in: " + arg1)
      end
    | let err: InvalidPercentEncoding val =>
      ph.fail("unexpected error for: " + arg1)
    end

class \nodoc\ iso _PropertyQueryParamsInvalidRejected
  is Property1[String val]
  """Query strings with invalid percent-encoding produce errors."""
  fun name(): String => "uri/query_parameters/invalid_rejected"

  fun gen(): Generator[String val] =>
    Generators.one_of[String val]([
      "key=%GG"; "k=%2"; "a=b&c=%"; "bad=%XX&good=1"; "%ZZ=val"
    ])

  fun ref property(arg1: String val, ph: PropertyHelper) =>
    match ParseQueryParameters(arg1)
    | let parsed: Array[(String val, String val)] val =>
      ph.fail("expected error for: " + arg1)
    | let err: InvalidPercentEncoding val =>
      ph.assert_true(true)
    end

class \nodoc\ iso _TestQueryParametersKnownGood is UnitTest
  """Known query parameter parsing cases."""
  fun name(): String => "uri/query_parameters/known_good"

  fun ref apply(h: TestHelper) =>
    // Simple key-value pairs
    _assert_params(h, "a=1&b=2",
      [("a", "1"); ("b", "2")])

    // Plus as space
    _assert_params(h, "key=hello+world",
      [("key", "hello world")])

    // Duplicate keys preserved in order
    _assert_params(h, "a=1&a=2",
      [("a", "1"); ("a", "2")])

    // Empty string produces empty array
    _assert_params(h, "", Array[(String val, String val)](0))

    // Key without value (no =)
    _assert_params(h, "key",
      [("key", "")])

    // Key with empty value
    _assert_params(h, "key=",
      [("key", "")])

    // Multiple keys without values
    _assert_params(h, "a&b&c",
      [("a", ""); ("b", ""); ("c", "")])

    // Percent-encoded key and value
    _assert_params(h, "hello%20world=foo%26bar",
      [("hello world", "foo&bar")])

    // Value with multiple = signs (only first splits)
    _assert_params(h, "key=a=b=c",
      [("key", "a=b=c")])

    // Mixed forms
    _assert_params(h, "a=1&b&c=3",
      [("a", "1"); ("b", ""); ("c", "3")])

  fun _assert_params(
    h: TestHelper,
    input: String val,
    expected: Array[(String val, String val)] val)
  =>
    match ParseQueryParameters(input)
    | let parsed: Array[(String val, String val)] val =>
      h.assert_eq[USize](expected.size(), parsed.size(),
        "pair count mismatch for: " + input)
      var i: USize = 0
      while i < expected.size() do
        try
          (let ek, let ev) = expected(i)?
          (let pk, let pv) = parsed(i)?
          h.assert_eq[String val](ek, pk,
            "key mismatch at " + i.string() + " for: " + input)
          h.assert_eq[String val](ev, pv,
            "value mismatch at " + i.string() + " for: " + input)
        end
        i = i + 1
      end
    | let err: InvalidPercentEncoding val =>
      h.fail("parse failed for: " + input + ": " + err.string())
    end
