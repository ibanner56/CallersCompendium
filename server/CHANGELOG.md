# Changelog

All notable changes to the Athenaeum server are documented in this file.

The server package has its own version history. Its releases are independent of
the app and of `compendium_core`; version headings below refer to
`server/pubspec.yaml`.

## [Unreleased]

### Fixed

- The per-IP request and failed-resolution limits now count an IPv6 client by
  its /64 instead of its full address. A single IPv6 subscriber can present 2^64
  addresses inside its delegated /64, so each used to get a fresh bucket, the
  limit never bound it, and minting addresses could evict honest clients from
  the bounded bucket tables. IPv4 clients, and IPv4-mapped IPv6 addresses
  (`::ffff:a.b.c.d`, keyed as the IPv4 address), are still counted per address.
  The rule applies to both the socket peer and the loopback-trusted
  `X-Forwarded-For` value. No configuration or schema change.

## [0.3.1] - 2026-10-17

### Changed

- The `compendium_core` dependency advances to `0.9.0`, taking the schema from v39 → v40 for syncing your own figures and your notes on built-in figures. The generated sync allow-list now accepts the `glossaryEntry` record kind (`createdAt`, `definition`, `description`, `id`, `keywords`, `kind`, `name`, `notes`, `payload`) and the `figureNote` record kind (`id`, `notes`). Deploy this server before clients on app `0.8.0`: older servers reject the new records and fields. Clients can now skip record kinds they do not know in a peer manifest; the server still decodes manifests strictly and rejects them. The server's own code is unchanged.

## [0.3.0] - 2026-10-14

### Fixed

- The reference Apache vhost (`server/deploy/athenaeum.conf`) proxied
  `/heartbeat` to `/heartbeat/heartbeat`, because a `ProxyPassMatch` target
  without a backreference has the request path appended, so the liveness check
  and the status page that polls it got the server's `404`. Both vhosts now
  capture the path and pass it on. Existing deployments must update their
  installed vhost and reload Apache; the server itself is unchanged.

### Changed

- The request-rate limits are counted per second (sync spec §5.4): 5 requests
  a second per client IP with a burst of 300, was 60 a minute with a burst of
  120, and 15 a second per store with a burst of 600, was 600 a minute.
  `AthenaeumBudgetLimits.perIpRequestsPerSecond` and `perStoreRequestsPerSecond`
  replace the per-minute fields. The failure and creation budgets are
  unchanged and still per minute.

- The `compendium_core` schema advances from v38 → v39 for Device Sync
  bookkeeping. The generated sync allow-list diff is empty, so this bump added
  no shareable wire fields or record kinds. Clients running app `0.7.0` continue
  to sync against older servers through one-blob requests; deploy server
  `0.3.0` to enable the batch blob endpoints and per-second request budgets.

### Added

- A reference alert forwarder in `server/deploy/`: `athenaeum-alert-email`
  emails each `quota_exhaustion` or `sweep_failure` line the container writes,
  and `athenaeum-alert-email.service` feeds it from `docker logs --follow`. A
  failed send is logged and skipped rather than stopping the forwarder. The
  operations runbook installs it as first-deployment step 6, and now also
  checks the root filesystem for `discard`, which stalled synced writes for
  over half an hour after large deletions on the reference host.

- `POST /v1/blobs/batch` returns the blobs for up to 200 hashes in one
  response (sync spec §5.2): a frame per hash, in request order, carrying the
  blob or saying it is missing, or that the 2 MB response cap was reached
  before it. The response is streamed one blob at a time and gzip-compressed
  when the client accepts it. A store that does not resolve counts as a failed
  resolution, as on every store-scoped route. A batch of *n* hashes costs
  1 + ⌈*n*/20⌉ tokens of both the per-IP and the per-store request limits
  (`AthenaeumBudgetLimits.blobBatchHashesPerToken`, default 20); one either
  limit cannot cover is refused `429` whole, with a `Retry-After` computed for
  that batch. `GET /v1/blobs/{hash}` is unchanged.
- `PUT /v1/blobs/batch` stores up to 50 blobs in one request and one
  transaction (sync spec §5.2): the body is the batch read's frames, every one
  a blob, and the `200` response gives each blob the status its own
  `PUT /v1/blobs/{hash}` would get, in request order. Once one new blob would
  pass the store quota, it and every later new blob in the batch is `507`. A
  body over 50 blobs, with a blob over 1 MB, a duplicate hash or a frame that is
  not a blob is refused whole. A gzip body is not held to the 10× expansion
  ratio; the absolute cap bounds it. A batch of *n* blobs costs 1 + ⌈*n*/10⌉
  tokens of both the per-IP and the per-store request limits
  (`AthenaeumBudgetLimits.blobUploadBlobsPerToken`, default 10), charged once
  the store resolves; one either limit cannot cover is refused `429` whole,
  storing nothing. `PUT /v1/blobs/{hash}` is unchanged.

## [0.2.2] - 2026-10-01

### Fixed

- `POST /v1/blobs/missing` reports a blob whose reference survives but whose
  file is gone, and a repeated `PUT` of the same bytes now restores the file
  without charging quota again or changing the reference. A body that does not
  match the recorded size or hash is rejected `400`.

### Changed

- Request-path cleanup retry stops between jobs once a 50 ms monotonic-clock budget
  is spent (at least one job always runs). Startup orphan reconciliation walks
  one store epoch at a time and queues each epoch in a single transaction.
  
### Security

- Gzip request bodies are now capped on their encoded (wire) size per route, and
  an over-long `Content-Length` on a gzip body is rejected up front with `413`.
  Previously a stream of empty gzip members decoded to no chunks and evaded the
  size checks.
- When forwarded headers are trusted (loopback peer), the rightmost
  `X-Forwarded-For` entry keys the per-client budget instead of the leftmost.
  Behaviour behind the reference Apache (which overwrites the header) is
  unchanged.

## [0.2.1] - 2026-09-24

### Changed

- `PUT /v1/blobs/{hash}` answers `404 store not found` instead of
  `409 stale blob epoch` when the store is deleted or reaped mid-request, and
  counts the response against the failed-resolution budget. No blob endpoint
  emits `409`, which the specification reserves for a stale-epoch manifest `PUT`
  and a duplicate `POST /v1/store`.

### Removed

- The compile-time `ATHENAEUM_PEPPER` fallback. The pepper now comes only from
  runtime configuration — the environment variable or `--pepper` — so a build
  cannot embed one and a server with none configured refuses to start. The
  documented local example passes it through the environment rather than argv,
  where the process list exposes it to other users on the host.

## [0.2.0] - 2026-09-19

### Added

- Serve a dedicated static status page from the Apache root instead of the
  default Apache homepage.
- Add a credential-free `/heartbeat` readiness endpoint and use it to back the
  public status badge.
- Add the W16 Linux host-network Docker and Apache deployment reference,
  trusted real-client address resolution, and safe operational alerts.
- Add a supported break-glass manifest read command that records its separate
  audit row before access.
- Use Apache's underlying connection peer for forwarded-address trust even when
  host-level remote-IP rewriting is enabled.
- Bound repeated operational alerts with the same kind, source, and exception
  type to one notification each minute, carrying an aggregate count for
  subsequent notifications.
- Add the initial Shelf-based Device Sync server with SQLite metadata,
  epoch-namespaced immutable blobs, store and manifest endpoints, credential
  validation, and allocation-safe request limits.
- Validate recognizable record blobs against the shared generated privacy
  allow-list while tolerating newer envelope versions.
- Add 30-day store retention, 24-hour upload grace-period garbage collection,
  aggregate store quotas, a privacy-safe break-glass access log, and a bounded
  diagnostic-event store with privacy filtering and 30-day retention.

### Fixed

- Count device manifest bodies toward the per-store byte quota. Manifest and
  blob uploads and store metadata now include manifest bytes, and a manifest
  upload that would exceed the quota is refused with `507` before its body is
  buffered, charging a replacement only for its size difference.

- Reject incomplete record-like blob envelopes before privacy allow-list
  validation so private fields cannot bypass the boundary by omitting `v`.

- Route Apache error logs through a redactor so module messages cannot persist
  request targets.
- Serialize store deletion with durable filesystem cleanup retries, preserve
  stale-epoch blob uploads for later collection, and return `400` for malformed
  gzip request bodies.
- Return `200` for existing manifest updates, decode hexadecimal peppers
  unambiguously, preserve blob upload timestamps on duplicate writes, and
  refund failed store-creation reservations.
- Delete stores immediately regardless of upload grace, and remove old
  unreferenced blobs across all persisted epochs after manifest publication or
  the hourly sweep.
- Rotate failed filesystem cleanup jobs so bounded retry batches make progress
  past permanently failing or ref-protected entries.
- Preflight manifest and blob quotas before reading request bodies, keep pending
  filesystem deletions charged against blob and byte quotas (including failed
  whole-store removals), sweep stale epochs, bound request-path deletion
  retries (including post-manifest collection), preserve epochs that regain
  stale refs, prioritize immediate store cleanup, and keep periodic cleanup
  alive across transient failures.
- Skip unnecessary manifest decoding during garbage collection and avoid
  persisting diagnostics for credentials that do not resolve to a store.
- Keep committed store deletion successful when post-commit cleanup encounters
  a database error, scope pending-reference accounting to queued directories,
  index linkable break-glass records for bounded retention purges, index store
  activity timestamps for hourly expiry scans, clear redundant per-blob cleanup
  jobs after successful whole-directory deletion, and reconcile crash-orphaned
  final blob files and temporary upload artifacts into the durable cleanup queue
  at startup, charge pending physical files against quotas, and isolate
  request-path cleanup failures from protocol responses.
- Preserve smoke-test cleanup credentials across ambiguous create responses,
  generate unique per-run test stores, and keep release-gate ordering before
  tagging and publication.
