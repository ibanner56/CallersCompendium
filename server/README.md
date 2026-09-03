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
durable cleanup record retries failed filesystem removal in a larger bounded
batch on requests and server start, and the hourly sweep drains the remainder.
Request-path retry failures are isolated so they do not change protocol
responses.
Startup reconciliation also queues crash-orphaned final blob files and temporary
upload artifacts for the same cleanup path. Every pending physical file remains
charged against recreated-store quotas, and an epoch that gains a stale upload is
preserved until its refs are gone. Store deletion also prioritizes all
directories belonging to that store before background retries.
Stores are reaped after 30 days without an authenticated request.
Unreferenced blobs remain temporary roots for 24 hours so an in-flight upload
can be published safely; manifest publication collects expired blobs across all
persisted epochs, and `DELETE /v1/store` bypasses that grace period. The
break-glass access database makes a derived sync storage path eligible for nulling
after 30 days and nulls it by the next hourly sweep, then retains only its
timestamp.
Ordinary diagnostic events become eligible for removal after 30 days and are
removed by the next hourly sweep; unauthenticated failures are not persisted,
and the diagnostic store is capped at 10,000 rows with a timestamp index.
