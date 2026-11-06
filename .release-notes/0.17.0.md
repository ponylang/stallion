## Fix unnecessary heap allocations in string() on value types

`string()` on `Method`, `Status`, `MediaType`, `NoAcceptableType`, and internal value types was heap-allocating on every call. `Stringable` requires a `String iso^` return, so each implementation called `.clone()` on a string literal — turning a free interned lookup into a heap allocation. These types now return `String val`, and the compiler interns the literals.

## Remove Stringable conformance from Method, Status, MediaType, and NoAcceptableType

`Method`, `Status`, `MediaType`, and `NoAcceptableType` no longer conform to `Stringable`. Their `string()` methods return `String val` instead of `String iso^`.

Code that passes one of these types where `Stringable` is expected needs to call `string()` explicitly:

Before:

```pony
fun log(s: Stringable) => _env.out.print(s.string())

log(GET)  // worked when GET was Stringable
```

After:

```pony
log(GET.string())
```

Code that consumed the `iso` return also needs updating:

Before:

```pony
let s: String iso = GET.string()
```

After:

```pony
let s: String val = GET.string()
```
## Update to work with ponyc 0.78.0

ponyc 0.78.0 changed the `Stringable` interface. `string()` now returns `String` instead of `String iso^`. We have updated accordingly.

