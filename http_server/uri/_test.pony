use "pony_test"
use "pony_check"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    // Percent-encoding tests
    test(Property1UnitTest[String val](_PropertyPercentRoundtrip))
    test(Property1UnitTest[String val](
      _PropertyPercentEncodeOutputLegal))
    test(Property1UnitTest[String val](
      _PropertyInvalidPercentSequenceRejected))
    test(Property1UnitTest[(String val, Bool)](
      _PropertyPercentDecodeBoundary))
    test(_TestPercentEncodeKnownGood)

    // URI parsing tests
    test(Property1UnitTest[_ValidURIInput](_PropertyURIRoundtrip))
    test(Property1UnitTest[String val](_PropertyInvalidSchemeRejected))
    test(_TestParseURIKnownGood)

    // Authority parsing tests
    test(Property1UnitTest[_ValidAuthorityInput](
      _PropertyAuthorityRoundtrip))
    test(Property1UnitTest[String val](_PropertyInvalidPortRejected))
    test(Property1UnitTest[String val](_PropertyInvalidHostRejected))
    test(_TestParseURIAuthorityKnownGood)

    // Path segment tests
    test(Property1UnitTest[String val](_PropertyPathSegmentCount))
    test(Property1UnitTest[String val](_PropertyPathSegmentRoundtrip))
    test(Property1UnitTest[String val](_PropertyPathSegmentInvalidRejected))
    test(_TestPathSegmentsKnownGood)

    // Query parameter tests
    test(Property1UnitTest[Array[(String val, String val)] val](
      _PropertyQueryParamsRoundtrip))
    test(Property1UnitTest[String val](_PropertyQueryParamsPlusDecodes))
    test(Property1UnitTest[String val](_PropertyQueryParamsInvalidRejected))
    test(_TestQueryParametersKnownGood)
