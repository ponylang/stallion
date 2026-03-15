## Added cookie parsing and serialization

Stallion now provides built-in cookie support in two directions: reading cookies from requests and building `Set-Cookie` response headers.

Cookies are automatically parsed from `Cookie` request headers and available on the `Request` object. Use `request'.cookies.get("name")` to look up a cookie by name, or `request'.cookies.values()` to iterate over all parsed cookies:

```pony
fun ref on_request_complete(request': stallion.Request val,
  responder: stallion.Responder)
=>
  match request'.cookies.get("session")
  | let token: String val =>
    // Use the session token
  end
```

For direct parsing outside the request lifecycle, `ParseCookies` accepts a raw `Cookie` header value string or a `Headers val` collection.

To build `Set-Cookie` response headers, use `SetCookieBuilder`. It defaults to `Secure`, `HttpOnly`, and `SameSite=Lax` — override explicitly when needed:

```pony
match stallion.SetCookieBuilder("session", token)
  .with_path("/")
  .with_max_age(3600)
  .build()
| let sc: stallion.SetCookie val =>
  // Add to response: .add_header("Set-Cookie", sc.header_value())
| let err: stallion.SetCookieBuildError =>
  // Handle validation error
end
```

The builder validates cookie names (RFC 2616 token), values (RFC 6265 cookie-octets), and path/domain attributes (no CTLs or semicolons), enforces `__Host-` and `__Secure-` prefix rules, and checks `SameSite=None` + `Secure` consistency.

New types: `Header`, `RequestCookie`, `RequestCookies`, `ParseCookies`, `SetCookie`, `SetCookieBuilder`, `SetCookieBuildError`, `SameSite` (`SameSiteStrict`, `SameSiteLax`, `SameSiteNone`).

## Changed Headers.values() to yield Header val instead of tuples

`Headers.values()` now yields `Header val` objects instead of `(String, String)` tuples. Code that destructures header values needs to change from field access on tuples to field access on the `Header` class:

Before:

```pony
for (name, value) in headers.values() do
  env.out.print(name + ": " + value)
end
```

After:

```pony
for hdr in headers.values() do
  env.out.print(hdr.name + ": " + hdr.value)
end
```
