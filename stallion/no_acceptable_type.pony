primitive NoAcceptableType is Stringable
  """
  Returned by `ContentNegotiation` when none of the server's supported
  media types match the client's `Accept` header preferences.

  Servers should respond with 406 Not Acceptable when they receive this
  result.
  """
  fun string(): String iso^ => "NoAcceptableType".clone()
