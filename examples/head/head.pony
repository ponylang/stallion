"""
HTTP server that handles HEAD correctly. A GET request gets a body; a HEAD
request gets the same headers a GET would, including Content-Length, but no
body, as required by RFC 9110.

Stallion sends exactly the bytes the handler builds and never rewrites a
response, so suppressing the body for HEAD is the handler's job. This example
shows the pattern: build the headers once, then add the body chunk only when
the method is not HEAD.

Try it:
  curl -i http://localhost:8080/      # GET: headers and body
  curl -I http://localhost:8080/      # HEAD: same headers, no body
"""
