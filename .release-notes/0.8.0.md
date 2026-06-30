## Drop support for Windows 10

Building stallion for Windows now requires ponyc 0.66.0 or later and Windows 11 or Windows Server 2022 or later. Windows 10 is no longer supported. Non-Windows platforms are unaffected.

On Windows, backpressure notifications (`on_throttled`/`on_unthrottled`) now fire based on whether the operating system can actually accept more data, matching the behavior on other platforms. Previously they could fire based on an internal heuristic that did not reflect the real state of the socket.

## Fix idle timeout never closing stalled connections

A connection that stalled in the middle of a request or response — a client that stopped reading or sending — was never closed by the idle timeout and held the connection open indefinitely, letting a slow or stuck client exhaust the server. The idle timeout now closes any connection with no activity for the configured time, wherever it is in the request/response cycle. Connections still actively transferring data are not affected — they keep the connection alive.

## Fix connections closed mid-transfer by the idle timeout

A connection could be closed by its idle timeout while it was still actively transferring data to a slow peer. A large transfer draining slowly to a slow reader looked idle even though data was still moving, so it was closed mid-transfer. A connection is now closed by the idle timeout only when no data has moved in either direction for the timeout.

## Fix on_closed firing twice when a backpressured connection closes

When a connection was closed while under write backpressure, the `on_closed` callback fired twice. It now fires exactly once.

