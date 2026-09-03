# Athenaeum server

This package contains the self-hostable HTTP service used by Device Sync. It
binds a loopback address by default; TLS termination and the public reverse
proxy are deployment concerns covered by ADR-004 and W16.

## Run locally

From the repository root:

```sh
openssl rand -base64 32 > /secure/path/athenaeum.pepper
chmod 600 /secure/path/athenaeum.pepper
dart run server/bin/athenaeum.dart \
  --data-dir /tmp/athenaeum \
  --pepper "$(cat /secure/path/athenaeum.pepper)"
```

The pepper is required, is never stored in SQLite, and must be at least 256
bits of cryptographically secure randomness. Set `ATHENAEUM_PEPPER` instead of
`--pepper` when passing it as a command-line argument is undesirable.

Generate the pepper once and persist it in a secret store before starting the
service. Reuse that same value for every restart of a data directory. The
service listens on `127.0.0.1:33333` unless the loopback-only `--host`
(`127.0.0.1` or `localhost`) and `--port` are provided. Public listener
addresses are rejected. This local listener is for C2/client development; production TLS,
proxy forwarding, and address handling are specified for W16. Logging, alerting,
retention, and break-glass procedures are specified for W12.

Store deletion removes the epoch directory immediately when possible; a
durable cleanup record retries failed filesystem removal on the next request or
server start.
