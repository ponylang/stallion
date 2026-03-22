## Fix premature idle timeouts on SSL connections

HTTPS connections with an idle timeout configured could be closed during the TLS handshake, before the connection was ready for application data. The idle timer is now deferred until the handshake completes.

