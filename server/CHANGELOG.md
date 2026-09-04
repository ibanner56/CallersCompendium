# Changelog

All notable changes to the Athenaeum server are documented in this file.

The server package has its own version history. Its releases are independent of
the app and of `compendium_core`; version headings below refer to
`server/pubspec.yaml`.

## [Unreleased]

### Added

- Add the W16 Linux host-network Docker and Apache deployment reference,
  trusted real-client address resolution, and safe operational alerts.
- Add a supported break-glass manifest read command that records its separate
  audit row before access.
- Use Apache's underlying connection peer for forwarded-address trust even when
  host-level remote-IP rewriting is enabled.
- Bound repeated operational alerts to one notification per kind and source
  each minute, carrying an aggregate count for subsequent notifications.
- Add the initial Shelf-based Device Sync server with SQLite metadata,
  epoch-namespaced immutable blobs, store and manifest endpoints, credential
  validation, and allocation-safe request limits.
- Validate recognizable record blobs against the shared generated privacy
  allow-list while tolerating newer envelope versions.
- Add 30-day store retention, 24-hour upload grace-period garbage collection,
  aggregate store quotas, a privacy-safe break-glass access log, and a bounded
  diagnostic-event store with privacy filtering and 30-day retention.

### Fixed

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
