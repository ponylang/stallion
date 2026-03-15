use "pony_check"
use "pony_test"

class \nodoc\ iso _TestHTTPDateKnownGood is UnitTest
  """
  Verify exact output for known epoch values.
  """
  fun name(): String => "http_date/known_good"

  fun apply(h: TestHelper) =>
    // Epoch 0 = Thursday, 01 Jan 1970 00:00:00 GMT
    h.assert_eq[String val](
      "Thu, 01 Jan 1970 00:00:00 GMT",
      _HTTPDate(0),
      "epoch 0")

    // Known RFC date: Mon, 01 Dec 2025 12:30:45 GMT
    h.assert_eq[String val](
      "Mon, 01 Dec 2025 12:30:45 GMT",
      _HTTPDate(1764592245),
      "2025-12-01 12:30:45")

    // Leap year: Sat, 29 Feb 2020 00:00:00 GMT
    // 2020-02-29 00:00:00 UTC = 1582934400
    h.assert_eq[String val](
      "Sat, 29 Feb 2020 00:00:00 GMT",
      _HTTPDate(1582934400),
      "leap year 2020-02-29")

class \nodoc\ iso _PropertyHTTPDateFormat is Property1[I64]
  """
  Every formatted date has the correct structure:
  3-char day, comma, space, 2-digit day, space, 3-char month, space,
  4-digit year, space, HH:MM:SS, space, "GMT".
  """
  fun name(): String => "http_date/format_structure"

  fun gen(): Generator[I64] =>
    // Generate dates between 1970 and 2099
    Generators.i64(0, 4_102_444_800)

  fun ref property(arg1: I64, ph: PropertyHelper) =>
    let result = _HTTPDate(arg1)

    // Length should be 29 characters: "Thu, 01 Jan 1970 00:00:00 GMT"
    ph.assert_eq[USize](29, result.size(),
      "Expected 29 chars, got " + result.size().string() +
        ": '" + result + "'")

    // Ends with " GMT"
    ph.assert_true(result.contains(" GMT"),
      "Should end with GMT: " + result)

    // Has comma at position 3
    try
      ph.assert_eq[U8](',', result(3)?,
        "Position 3 should be comma: " + result)
    else
      ph.fail("Result too short: " + result)
    end

    // Has colons at positions 19 and 22 (time separators)
    try
      ph.assert_eq[U8](':', result(19)?,
        "Position 19 should be colon: " + result)
      ph.assert_eq[U8](':', result(22)?,
        "Position 22 should be colon: " + result)
    else
      ph.fail("Result too short for time check: " + result)
    end
