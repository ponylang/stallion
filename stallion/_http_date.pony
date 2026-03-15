use "time"

primitive _HTTPDate
  """
  Format epoch seconds as an IMF-fixdate string (RFC 7231 §7.1.1.1).

  Example: `Thu, 01 Jan 1970 00:00:00 GMT`

  Used by `SetCookieBuilder` for the `Expires` attribute.
  """

  fun apply(epoch_seconds: I64): String val =>
    """Format epoch seconds as an IMF-fixdate string."""
    let d = PosixDate(epoch_seconds)

    // PosixDate.day_of_week uses C's tm_wday: 0=Sunday through 6=Saturday
    let day_names = [as String val:
      "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat"]
    let month_names = [as String val:
      "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"
      "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec"]

    let day_name = try
      day_names(d.day_of_week.usize())?
    else
      _Unreachable()
      "Thu"
    end

    let month_name = try
      month_names((d.month - 1).usize())?
    else
      _Unreachable()
      "Jan"
    end

    let buf = recover val
      String(29)
        .>append(day_name)
        .>append(", ")
        .>append(_pad2(d.day_of_month))
        .>append(" ")
        .>append(month_name)
        .>append(" ")
        .>append(d.year.string())
        .>append(" ")
        .>append(_pad2(d.hour))
        .>append(":")
        .>append(_pad2(d.min))
        .>append(":")
        .>append(_pad2(d.sec))
        .>append(" GMT")
    end
    buf

  fun _pad2(n: I32): String val =>
    """Zero-pad an integer to two digits."""
    if n < 10 then
      "0" + n.string()
    else
      n.string()
    end
