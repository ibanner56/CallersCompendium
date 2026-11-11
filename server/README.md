# Athenaeum server

This package contains the self-hostable HTTP service used by Device Sync. It
binds a loopback address by default; TLS termination and the public reverse
proxy are deployment concerns covered by ADR-004 and W16. The supported
production topology is a Linux host running Apache plus a Docker container
started with `--network host`; see
[`docs/dev/athenaeum-operations.md`](../docs/dev/athenaeum-operations.md).

## Run locally

From the repository root:

```sh
openssl rand -base64 32 > /secure/path/athenaeum.pepper
chmod 600 /secure/path/athenaeum.pepper
ATHENAEUM_PEPPER="$(cat /secure/path/athenaeum.pepper)" \
  dart run server/bin/athenaeum.dart --data-dir /tmp/athenaeum
```

The pepper is required, is never stored in SQLite, and must be at least 256
bits of cryptographically secure randomness. It comes only from runtime
configuration — the `ATHENAEUM_PEPPER` environment variable above, or the
`--env-file` flow the [operations
runbook](../docs/dev/athenaeum-operations.md) uses for deployment. No build
can embed one: the server reads no compile-time value and refuses to start
when no pepper is configured rather than substituting a default.

A `--pepper <value>` option also exists, but **prefer the environment
variable**: command-line arguments are visible to every other user on the host
(`ps -o args`), so `--pepper` leaks the deployment secret on a shared machine.
Use it only where nothing else can see the process list.

### Break-glass reads

After incident approval, use the supported break-glass command rather than
querying SQLite or the blob directory directly. It accepts the raw sync ID on
stdin and reads exactly one item per run: one device's manifest
(`--break-glass-device-id`) or one blob (`--break-glass-blob <hash>`), in the
store's current epoch unless `--break-glass-epoch` names another. Before it
looks the store up it records, in the separate break-glass database, an access
row and a row naming what it is about to read (manifest and device ID, or blob
and hash, with the requested epoch); when no epoch was requested it records the
current one after the lookup. If either write fails it reads nothing. It never
records the content. Then it writes the item's bytes to stdout:

```sh
printf '%s\n' "$SYNC_ID" | docker exec -i athenaeum \
  /opt/athenaeum/bin/athenaeum --data-dir /var/lib/athenaeum --break-glass \
  --break-glass-device-id device-one > /secure/incident/manifest.bin
printf '%s\n' "$SYNC_ID" | docker exec -i athenaeum \
  /opt/athenaeum/bin/athenaeum --data-dir /var/lib/athenaeum --break-glass \
  --break-glass-blob "$BLOB_HASH" > /secure/incident/blob.bin
```

Keep the input, output, and audit evidence in approved secure locations.

Generate the pepper once and persist it in a secret store before starting the
service. Reuse that same value for every restart of a data directory. The
service listens on `127.0.0.1:33333` unless the loopback-only `--host`
(`127.0.0.1` or `localhost`) and `--port` are provided. Public listener
addresses are rejected. This local listener is for C2/client development;
production TLS, proxy forwarding, and address handling are specified for W16.
Logging, alerting, retention, and break-glass procedures are specified in the
W16 operations runbook.

For production, reserve port `33333` on the Linux host and run the container
with host networking. Apache must proxy only HTTPS `/v1/` requests to
`127.0.0.1:33333`; the plaintext `:80` vhost must refuse `/v1` rather than
redirecting it. The reference vhost serves the static status page at `/` from
`/var/www/athenaeum`, proxies the credential-free `/heartbeat` liveness check,
and proxies the API under `/v1/` only over HTTPS. Install the status page and
its [`deploy/status/icon.svg`](deploy/status/icon.svg) app icon at that
document root before enabling the vhost. The reference vhost is
[`deploy/athenaeum.conf`](deploy/athenaeum.conf), and the image is built with
`server/Dockerfile` from the repository root.

Store deletion removes the epoch directory immediately when possible; a
durable cleanup record retries failed filesystem removal in a larger bounded
batch on requests and server start, and the hourly sweep drains the remainder.
Request-path retry runs until a 50 ms monotonic-clock budget is spent, checked
between jobs (at least one job always runs, and a job that has started always
finishes, so one very large directory can still take longer), up to 1,000 jobs
shared by the directory and blob queues. While a backlog lasts, each request
therefore spends up to about 50 ms draining it before it is served. It stops
at the first job whose filesystem removal fails, which is requeued, so a job
that keeps failing costs each request one attempt rather than the whole
budget. Request-path retry failures are isolated so they do not change
protocol responses.
Quota checks charge each store for its pending physical files from a running
per-store total, adjusted as jobs are queued and run, rather than re-reading
the deletion queue and the filesystem on every check. Queuing a store's
garbage therefore stats each queued file once, inside the collection: a
manifest `PUT` that drops many blobs takes correspondingly longer, once. The
total is derived from the filesystem once per store after a restart, and
again after a change the server cannot account for file by file (a directory
job, a cleanup that fails part way, an upload that fails after writing its
file); each derivation takes time in proportion to that store's pending
deletions. A pending file removed by hand while the server runs is not seen
until the next derivation, so it stays charged against the store's quota until
then, at the latest until a restart.
The hourly sweep runs in slices of about 50 ms and yields between them, so
requests are served while it runs; a sweep still running when the next is due
is not overlapped. A store is reaped only if it is still past the disuse TTL
when its own deletion runs, so a request between slices keeps it.
Startup reconciliation also queues crash-orphaned final blob files and temporary
upload artifacts for the same cleanup path; it walks one store epoch at a time
and queues each epoch in a single transaction, but still runs before the server
accepts requests, so startup time grows with the size of the blob tree.
Startup also indexes the blob references of any manifest stored without them —
every manifest, on the first start of an image that has the index — so garbage
collection reads that index rather than decoding manifest bodies.
A blob whose reference survives but whose file has gone missing is reported by
`POST /v1/blobs/missing`, and a repeated `PUT` of the same bytes restores the
file without charging quota again. Every pending physical file remains
charged against recreated-store quotas, and an epoch that gains a stale upload is
preserved until its refs are gone. Store deletion also prioritizes all
directories belonging to that store before background retries.
Stores are reaped after 30 days without an authenticated request.
Unreferenced blobs remain temporary roots for 24 hours so an in-flight upload
can be published safely; manifest publication collects expired blobs across all
persisted epochs, and `DELETE /v1/store` bypasses that grace period. The
break-glass access database makes a derived sync storage path, and the epoch,
device ID, and blob hash of each item requested, eligible for nulling after 30 days
and nulls them by the next hourly sweep, then retains only each access's
timestamp and whether a manifest or a blob was read.
Ordinary diagnostic events become eligible for removal after 30 days and are
removed by the next hourly sweep; unauthenticated failures are not persisted,
and the diagnostic store is capped at 10,000 rows with a timestamp index.

## Load testing

`tool/load_test.dart` measures how many requests one server process serves, as
input to the request-rate limits in spec §5.4. It runs the real `AthenaeumApp`
in its own isolate, listening on a loopback port, with every rate budget lifted
unless `--shipped-request-limits` is given, so by default it measures the server
rather than the limits. It steps through several numbers of in-flight requests
per scenario: `store-get`, `blob-get`, `blob-put` (a fresh ~1.5 KB record blob),
and `first-sync` (one device uploading a whole library into a new store,
reported as time per device).

`blob-put`, `blob-get` and `first-sync` model the legacy per-record
`GET`/`PUT /v1/blobs/{hash}` path. Since the batch routes (#1734, #1747) the
app sends `PUT /v1/blobs/batch` and `POST /v1/blobs/batch` instead, and keeps
the per-record requests only as a fallback (a blob over the size cap, or a server
without the batch routes). The tool does not call the batch routes, so what they
cost in request budget is not measured here, and a `first-sync` request count
overstates what the shipped app sends.

```sh
cd server
dart run tool/load_test.dart --data-dir /path/to/a/new/directory/on/the/deployment/disk
dart run tool/load_test.dart --help
```

`--data-dir` must be a new, empty directory (or omitted, which uses a temporary
one that is deleted afterwards). The tool runs schema migrations in it and
creates fixture stores with fixed IDs, so it refuses a directory that already
holds anything: a live deployment's data directory, or the directory of an
earlier run. Never point it at a live data directory.

Add `--shipped-request-limits` to run with the shipped request-rate limits
instead of lifting them, each worker as its own client address, to see where
they refuse. The fixture stores' per-store buckets carry over between steps, and
workers retry a `429` at once rather than after a minute as the app does; the
failure and creation budgets stay lifted.

Run it on the hardware you deploy to, with `--data-dir` on the disk the server
will use. Every authenticated request commits a SQLite write and every blob
upload also flushes a file, so disk sync latency dominates and a tmpfs directory
does not represent a real disk. A supplied `--data-dir` is left in place
afterwards; delete it once you have the numbers.
