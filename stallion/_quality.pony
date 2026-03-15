use "constrained_types"

type _Quality is Constrained[U16, _QualityValidator]
  // Quality factor scaled to 0–1000 (representing 0.000–1.000).

type _MakeQuality is MakeConstrained[U16, _QualityValidator]
  // Constructs a `_Quality` from a `U16`. Returns `_Quality` on success
  // or `ValidationFailure` if the value exceeds 1000.

primitive _QualityValidator is Validator[U16]
  fun apply(value: U16): ValidationResult =>
    recover val
      if value <= 1000 then
        ValidationSuccess
      else
        ValidationFailure("quality must be between 0 and 1000")
      end
    end
