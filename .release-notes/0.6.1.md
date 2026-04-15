## Auto-rearm idle timer after ASIO subscription failure

Previously, when the idle timer's ASIO event subscription failed (e.g. `ENOMEM` from the kernel's `kevent` or `epoll_ctl`), the timer would be silently cancelled with no recovery. Idle connections would stop being reaped for the remainder of that connection's lifetime, letting stale connections accumulate under sustained kernel pressure.

The idle timer is now automatically re-armed using the originally configured duration, so idle-timeout protection resumes on the next ASIO turn. If the re-armed subscription also fails, re-arm attempts continue until one succeeds.

## Add `on_timer_failure` callback

User timers created with `HTTPServer.set_timer()` can fail asynchronously if their ASIO event subscription is lost (typically under kernel resource pressure). Previously, such failures were silent — the timer simply never fired.

The new `on_timer_failure()` callback on `HTTPServerLifecycleEventReceiver` reports these failures so applications can decide how to recover. The timer has already been cancelled before the callback fires — any `TimerToken` your actor was tracking from the originating `set_timer()` call is now stale. The application may call `set_timer()` again to retry, close the connection, or do nothing if the deadline no longer matters. The default is a no-op.

```pony
actor MyServer is HTTPServerActor
  // ...

  fun ref on_timer_failure() =>
    // The request deadline timer never armed. Abandon this request.
    _http.close()
```
