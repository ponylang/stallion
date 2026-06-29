## Drop support for Windows 10

Building stallion for Windows now requires ponyc 0.66.0 or later and Windows 11 or Windows Server 2022 or later. Windows 10 is no longer supported. Non-Windows platforms are unaffected.

On Windows, backpressure notifications (`on_throttled`/`on_unthrottled`) now fire based on whether the operating system can actually accept more data, matching the behavior on other platforms. Previously they could fire based on an internal heuristic that did not reflect the real state of the socket.

