# ADR-005: User-defined dance difficulty vocabulary

- **Status**: Proposed
- **Roadmap item**: Issue #1200
- **Deciders**: Maintainers

## Context

The app currently persists a three-value `DanceLevel` enum. Callers need to use
different difficulty vocabularies, reorder their levels, and rename levels
without rewriting every dance. Difficulty is also a live ordered search
dimension and travels through backups, shares, and device sync.

Changing the enum directly would make labels the identity, break old drafts and
archives, and make independently configured devices unable to reconcile a
dance's assignment safely. Deleting a referenced level would leave an invalid
dance unless the write boundary enforces the relationship.

## Decision

Persist difficulty levels as ordered records with immutable IDs, normalized
unique labels, and sync timestamps. The three shipped levels use fixed IDs so
existing databases and cross-installation archives decode deterministically;
user-created levels receive generated IDs. Dances persist the nullable level ID,
not the label. Renaming and reordering update the level record only.

Archives carry the vocabulary records and old enum-name archives decode through
the fixed shipped IDs. Restores and shares merge records by ID under explicit
conflict and atomicity rules. External importer labels that do not match a
configured level remain unspecified and produce the existing warning.

Deletion is a repository transaction: a level with any dance reference is
rejected, including a shipped level. Unreferenced levels may be soft-deleted
and their tombstones participate in device-sync conflict resolution.

## Rationale

Stable IDs preserve assignments across label edits and avoid treating a rename
as a destructive delete/add. Fixed shipped IDs make migration and common
archives deterministic, while generated IDs avoid collisions for new local
levels. Keeping the vocabulary in the core archive gives whole-app backups one
source of truth rather than duplicating it in settings.

Persisted labels were rejected because renaming would be indistinguishable from
deleting an old level and would make old drafts and archives ambiguous.
Auto-creating levels for arbitrary importer strings was rejected because an
external label has no trustworthy position or relationship to the recipient's
ordered scale.

## Consequences

The schema, archive, draft, sync, privacy, search, and UI contracts all need
versioned compatibility work. A level cannot be deleted while assigned, and
deleted-level tombstones must be retained long enough for sync convergence.
Older readers can warn when they encounter vocabulary-bearing archives rather
than silently dropping assignments.

## Revisit triggers

- A future shared taxonomy requires globally coordinated IDs instead of local
  custom vocabularies.
- Device Sync gains a conflict policy that supersedes ID-keyed record merges.
- Product requirements allow reassignment-on-delete rather than guarded deletion.
