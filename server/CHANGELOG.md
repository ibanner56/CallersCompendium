# Changelog

All notable changes to the Athenaeum server are documented in this file.

The server package has its own version history. Its releases are independent of
the app and of `compendium_core`; version headings below refer to
`server/pubspec.yaml`.

## [Unreleased]

### Added

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
