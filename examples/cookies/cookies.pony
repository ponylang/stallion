"""
Visit counter using cookies. Reads the `visits` cookie from the request,
increments it, and sets it back via `Set-Cookie`. Demonstrates both
`Request.cookies` for reading and `SetCookieBuilder` for writing cookies.

First visit returns "Visit #1", subsequent visits increment the counter.
"""
