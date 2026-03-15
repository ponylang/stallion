## Fix dispose() hanging when peer FIN is missed

Calling `dispose()` on a connection actor could hang indefinitely if the remote peer's FIN packet was missed due to edge-triggered event notification. This left the connection stuck in CLOSE_WAIT, which typically surfaced as test timeouts or connections that never cleaned up. The connection now performs an immediate teardown on `dispose()`, preventing the hang.
