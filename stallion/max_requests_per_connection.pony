use "constrained_types"

type MaxRequestsPerConnection is
  Constrained[USize, _MaxRequestsPerConnectionValidator]
  """
  A validated maximum number of requests per keep-alive connection.

  Must be at least 1. Use `MakeMaxRequestsPerConnection` to create:

  ```pony
  match \exhaustive\ MakeMaxRequestsPerConnection(1000)
  | let m: MaxRequestsPerConnection =>
    ServerConfig("0.0.0.0", "80" where max_requests_per_connection' = m)
  | let e: ValidationFailure =>
    // handle error — value was 0
  end
  ```
  """

type MakeMaxRequestsPerConnection is
  MakeConstrained[USize, _MaxRequestsPerConnectionValidator]
  """
  Constructs a `MaxRequestsPerConnection` from a `USize`.

  Returns `MaxRequestsPerConnection` on success or `ValidationFailure`
  if the value is 0.
  """

primitive _MaxRequestsPerConnectionValidator is Validator[USize]
  """Validates that the max requests value is at least 1."""
  fun apply(value: USize): ValidationResult =>
    recover val
      if value >= 1 then
        ValidationSuccess
      else
        ValidationFailure(
          "max_requests_per_connection must be at least 1")
      end
    end
