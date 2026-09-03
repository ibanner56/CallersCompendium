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

### Fixed

- Serialize store deletion with durable filesystem cleanup retries, preserve
  stale-epoch blob uploads for later collection, and return `400` for malformed
  gzip request bodies.
- Return `200` for existing manifest updates, decode hexadecimal peppers
  unambiguously, preserve blob upload timestamps on duplicate writes, and
  refund failed store-creation reservations.
