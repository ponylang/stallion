## Add on_start_failure callback to HTTPServerLifecycleEventReceiver

Server actors can now be notified when a connection fails before starting — for example, when an SSL handshake fails. Previously, these failures were silently swallowed, making SSL misconfigurations very hard to debug: the listener would report "listening" but every incoming connection would silently die.

Override `on_start_failure()` to log or take action:

```pony
actor MyServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _out: OutStream

  // ... constructor ...

  fun ref _http_connection(): stallion.HTTPServer => _http

  fun ref on_start_failure(reason: lori.StartFailureReason) =>
    match reason
    | lori.StartFailedSSL =>
      _out.print("SSL handshake failed for incoming connection")
    end
```

The callback has a default no-op, so existing code is unaffected. Neither `on_request()` nor `on_closed()` fires for connections that fail before starting — `on_start_failure()` is the only notification.
