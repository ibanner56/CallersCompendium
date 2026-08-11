import 'package:drift/drift.dart' show Variable;

import 'database.dart';
import 'utc_datetime.dart';

/// The causal tick: **one second**, pinned to storage granularity.
///
/// ## The invariant this exists to preserve
///
/// Every existence stamp must be **strictly greater than the value it
/// supersedes**, so that a revival always outranks the deletion it supersedes
/// and a deletion always outranks the revival it supersedes, *whatever the
/// clocks say*. That is the whole job. §6.4 resolves an equal `existenceAt` in
/// favour of the tombstone, so a stamp that merely ties is not "close enough" —
/// it silently loses.
///
/// ## Why one second, and why not to "tighten" it
///
/// The Device Sync specification writes the rule as
/// `max(localNow, currentExistenceAt + 1ms)`. A reader who meets `+ 1s` next to
/// Dart's millisecond-precision [DateTime] API will be tempted to tighten it
/// back to a millisecond. **Do not.** This schema stores every [DateTime] as
/// unix **seconds** — drift's default mapping, and what `dances.created_at` has
/// held since v1, where a 2026-01-01 stamp is the integer `1767225600`, not
/// `1767225600000`. A literal millisecond rounds away to nothing on the way to
/// disk: `current + 1ms` reads back as `current`, the new stamp ties with the
/// transition it supersedes, and the invariant above is broken. Delete a record
/// and hit Undo in the same second — an ordinary snackbar interaction, not an
/// edge case — and the undo loses.
///
/// One second is therefore not an arbitrary choice or a rounding-up of the
/// spec: it is *the smallest increment this column can represent*, which makes
/// it the smallest increment that can satisfy the invariant at all. The tick is
/// pinned to storage granularity, so if the storage precision ever changes,
/// this constant changes with it — and `existence_test.dart` asserts the
/// coupling directly (`existenceStampTick` must survive a round trip through
/// [unixSeconds] as a strict increase), so tightening it is a red test rather
/// than a silent regression.
///
/// ## Who decided what, so the reasoning is auditable
///
/// Two separate things, and only one of them is a ruling:
///
/// * **Storage precision stays at seconds** — decided by **@ibanner56**, on the
///   grounds that second- versus millisecond-level granularity is equivalent
///   for the work this application does. Not an assumption, and not a
///   conclusion reached here.
/// * **One second follows from that** — derived, not chosen. Given seconds on
///   disk, one second is the only increment that can satisfy the invariant, so
///   this constant is a consequence of the ruling above rather than a second
///   decision layered on it.
///
/// The specification now defines a **tick** as the smallest interval the
/// timestamp storage representation can distinguish, and states the rule as
/// `+ 1 tick` — pinned to storage rather than to a magnitude. This constant is
/// that tick for this schema, so the two agree by construction rather than by
/// coincidence.
const Duration existenceStampTick = Duration(seconds: _tickSeconds);

/// The tick in whole seconds — the single source for both the Dart reference
/// implementation above and the SQL below, so the two cannot disagree about it.
const int _tickSeconds = 1;

/// The causal existence stamp: `max(localNow, currentExistenceAt + 1 tick)`.
///
/// This is the **reference implementation** of the rule. The repositories do
/// not call it: they apply the same arithmetic in SQL (below) so that a
/// transition is one statement with no preceding read — both to keep it atomic
/// and because a read-then-write would add an N+1 to the bulk import paths,
/// which `test/imports/import_pipeline_test.dart` guards against by counting
/// queries. `test/storage/existence_test.dart` runs this function and the SQL
/// over the same table of cases and asserts they agree, so the two cannot
/// drift apart.
///
/// Deliberately **not** a bare clock read. A device whose clock is behind, or
/// which performs two existence transitions inside one tick, would otherwise
/// stamp a revival at or below the tombstone it is meant to supersede, and the
/// record would stay deleted. Taking the max against the current value makes
/// every transition strictly later than the one before it on that device,
/// independently of the clock — see [existenceStampTick] for the invariant in
/// full, and for why the increment is one second rather than one millisecond.
///
/// [current] is the row's existing `existence_at` (`null` for a record that has
/// never carried one — a fresh creation, or a row written by something that
/// bypassed the repositories). A null [current] means there is nothing to
/// supersede, so the plain clock is correct.
///
/// This is the *local decision* form of the rule. Sync-apply paths must not use
/// it: applying a peer's blob copies that peer's value verbatim, and quarantine
/// repair derives its value from a peer without reading a clock at all, because
/// a repairing device's clock is by definition untrusted. Neither path exists
/// yet — this migration ships no sync client.
DateTime nextExistenceStamp({required DateTime now, DateTime? current}) {
  assertUtc(now, 'now');
  final localNow = asUtc(now);
  if (current == null) return localNow;
  final superseding = asUtc(current).add(existenceStampTick);
  return superseding.isAfter(localNow) ? superseding : localNow;
}

/// Unix-seconds form of a stamp, matching drift's `DateTimeColumn` mapping.
int unixSeconds(DateTime at) => asUtc(at).millisecondsSinceEpoch ~/ 1000;

/// SQL form of [nextExistenceStamp], taking the clock as a bound parameter.
///
/// Every right-hand side in one SQLite `UPDATE` sees the row's **pre-update**
/// values, so this can read `existence_at` while assigning to it, and the
/// `deleted_at` assignment alongside it can be decided from the old
/// `deleted_at`. That is what lets a whole transition be a single statement.
///
/// `COALESCE(existence_at, 0)` covers a row that somehow carries no stamp (one
/// written by a path that bypasses the repositories): `0 + 1` is 1970, so the
/// `MAX` simply yields the clock, which is the right answer when there is
/// nothing to supersede.
const String _causalExistenceSql =
    'MAX(?, COALESCE(existence_at, 0) + $_tickSeconds)';

/// Resolves a caller-supplied write stamp, defaulting to the current instant.
///
/// The kinds whose *models* carry no timestamps (tags, choreographers, venues,
/// published sources, custom field defs, settings) are stamped at the storage
/// layer instead. The parameter stays open so tests can pin the clock, matching
/// the `{required DateTime at}` convention `DanceRepository.softDelete` already
/// uses; it defaults rather than being required so this migration does not have
/// to touch every caller of every `upsert`.
DateTime resolveStamp(DateTime? at) {
  if (at == null) return DateTime.now().toUtc();
  assertUtc(at, 'at');
  return asUtc(at);
}

/// Applies a live<->deleted transition to one row, in a single statement.
///
/// Sets `deleted_at` (to [at] when [deleted], else NULL), moves `updated_at` to
/// the same instant, and advances `existence_at` causally. Matching no rows is
/// a no-op, so deleting an unknown id behaves as it always did.
///
/// One shared [at] goes into both `deleted_at` and `updated_at`, and the
/// record's body is untouched. That pairing is deliberate and predates this
/// column: `updated_at` answers "which content is newer" and `deleted_at`
/// drives retention, while only `existence_at` orders the transition itself, so
/// nothing causal flows into either of the other two.
///
/// [table] and [keyColumn] are interpolated rather than bound because SQLite
/// cannot parameterise an identifier. Every call site passes a literal constant
/// naming a table in this schema; nothing user-supplied reaches them.
Future<void> stampExistenceTransition(
  CompendiumDatabase db, {
  required String table,
  required String keyColumn,
  required String key,
  required DateTime at,
  required bool deleted,
}) {
  assertUtc(at, 'at');
  final stamp = unixSeconds(at);
  return db.customStatement(
    'UPDATE $table SET deleted_at = ${deleted ? '?' : 'NULL'}, '
    'updated_at = ?, existence_at = $_causalExistenceSql '
    'WHERE $keyColumn = ?',
    [if (deleted) stamp, stamp, stamp, key],
  );
}

/// Fixes up the existence columns of the row an upsert has just written.
///
/// Run **after** the insert-or-update, which must not mention `deleted_at` or
/// `existence_at` itself — this statement needs their pre-upsert values to tell
/// the three cases apart:
///
/// * **Revival** (`deleted_at` was set) — an existence transition, so take the
///   causal stamp. Revival-by-upsert is not theoretical: `choreographers.name`,
///   `tags.name`, `custom_field_defs.key` and `settings.key` are unique, so
///   re-creating an entity with the same natural key lands on its tombstone
///   rather than inserting beside it. Clearing `deleted_at` here is also what
///   makes that re-creation *work at all*: drift emits an untargeted
///   `ON CONFLICT DO UPDATE`, which writes only the columns the companion
///   names, so a tag re-created after deletion would otherwise be stored onto
///   the tombstone, keep its `deleted_at`, and simply never appear.
/// * **Creation** (`existence_at` NULL, because the insert branch ran) — seed
///   the field from a plain clock.
/// * **Ordinary content edit** (row was live and already stamped) — *not* an
///   existence transition. Leave `existence_at` exactly as it was. Advancing it
///   here would make every save look like a deletion-or-revival to a peer,
///   which is precisely the `updated_at`/`existence_at` conflation the third
///   column exists to prevent.
///
/// See [stampExistenceTransition] on the interpolated identifiers.
Future<void> applyUpsertExistence(
  CompendiumDatabase db, {
  required String table,
  required String keyColumn,
  required String key,
  required DateTime at,
}) {
  assertUtc(at, 'at');
  final stamp = unixSeconds(at);
  return db.customStatement(
    'UPDATE $table SET existence_at = CASE '
    'WHEN deleted_at IS NOT NULL THEN $_causalExistenceSql '
    'WHEN existence_at IS NULL THEN ? '
    'ELSE existence_at END, '
    'deleted_at = NULL '
    'WHERE $keyColumn = ?',
    [stamp, stamp, key],
  );
}

/// The id an upsert must actually write, when a **tombstoned** row already
/// holds the incoming natural key.
///
/// Returns that row's id, or `null` when the key is free (or held by a *live*
/// row, which is a different situation entirely — see below).
///
/// `choreographers.name`, `tags.name` and `custom_field_defs.key` are UNIQUE,
/// and drift emits `ON CONFLICT("id") DO UPDATE`, i.e. targeted at the primary
/// key. A conflict on the *natural* key therefore does not update anything: it
/// raises `UNIQUE constraint failed`. Before schema v25 a deleted entity's row
/// was gone, so re-creating one under the same name always worked. With a
/// tombstone the name is still occupied while every read filters the row out,
/// so the name looks free and the insert then fails — the user deletes the tag
/// "Easy", types "Easy" again, and gets an error. That is a live regression,
/// not a theoretical one, because `_createTag` in the dance editor mints a
/// fresh UUID for every new tag rather than resolving the name first.
///
/// Adopting the tombstoned row's id is the specified resolution: for the
/// UNIQUE-key kinds, "UUID unknown, natural key matches" reconciles silently
/// onto the existing record. It is also the only one the foreign keys permit —
/// re-keying the old row to the caller's new id would break `dance_tags` /
/// `dance_authors` / `custom_field_values` rows, whose FKs are `ON DELETE
/// CASCADE` with no `ON UPDATE` action. Adoption keeps them, so a re-created
/// entity comes back attached to the records it was attached to before, exactly
/// as reviving it under its original id does.
///
/// A **live** row holding the key is deliberately left alone, so that case
/// still raises `UNIQUE constraint failed` exactly as it did before v25. This
/// function only restores the pre-v25 outcome for the case v25 introduced.
///
/// **Adoption clears the adopted row's join rows** ([joinTable] /
/// [joinColumn]), and that is the difference between adoption and revival. A
/// revival — the same id written again — is "this record is back", and keeps
/// its associations. Adoption is not: the caller minted a fresh UUID, so the
/// user is creating a *new* entity that happens to want a name a deleted one
/// still holds. Before v25 that produced an empty tag, because the hard delete
/// had cascaded the join rows away; keeping them would mean deleting the tag
/// "Easy" from two hundred dances and then re-creating "Easy" silently
/// re-tagged all two hundred. Reusing the old row's id is an implementation
/// detail forced by the foreign keys, and must not leak into what the user
/// sees.
///
/// Only `tags` can actually reach this state — `choreographers` and
/// `custom_field_defs` are referentially guarded, so a tombstoned row of theirs
/// has no join rows to clear. The clearing is written for all three anyway, so
/// that relaxing a guard cannot quietly reintroduce the surprise.
Future<String?> adoptTombstonedNaturalKey(
  CompendiumDatabase db, {
  required String table,
  required String keyColumn,
  required String naturalKeyColumn,
  required String naturalKey,
  required String incomingId,
  required String joinTable,
  required String joinColumn,
}) async {
  final rows = await db
      .customSelect(
        'SELECT $keyColumn AS adopted FROM $table '
        'WHERE $naturalKeyColumn = ? AND $keyColumn != ? '
        'AND deleted_at IS NOT NULL LIMIT 1',
        variables: [
          Variable.withString(naturalKey),
          Variable.withString(incomingId),
        ],
      )
      .get();
  if (rows.isEmpty) return null;
  final adopted = rows.single.read<String>('adopted');
  await db.customStatement('DELETE FROM $joinTable WHERE $joinColumn = ?', [
    adopted,
  ]);
  return adopted;
}

/// Seeds `existence_at` on a row that has never carried one, and touches
/// nothing else.
///
/// `dances` and `programs` are written through a plain upsert that takes every
/// stamp from the model, and the model carries no `existenceAt` — deliberately,
/// since nothing reads it yet and adding it would ripple through the archive
/// codec, equality and the editors for no gain. So creation has to seed the
/// column here instead, or a brand-new dance would carry NULL and lose every
/// existence comparison against a migrated one (which holds T0).
///
/// `WHERE existence_at IS NULL` is what makes this safe to run on every write:
/// it fires exactly once per row, so an ordinary content edit cannot move the
/// value. Genuine transitions go through [stampExistenceTransition].
///
/// The seed is `COALESCE(deleted_at, created_at)`, mirroring the v25 migration
/// back-fill with the record's own creation time standing in for T0. Both
/// branches say when the record's *existence* last changed: a new record began
/// to exist when it was created, and an archive-restored tombstone last changed
/// when it was deleted. Note what this is **not**: `updated_at`. Seeding from
/// the content stamp would make an imported record's ordinary edit history look
/// like a string of existence transitions — the same coupling the migration
/// back-fill exists to avoid.
Future<void> seedExistenceIfMissing(
  CompendiumDatabase db, {
  required String table,
  required String keyColumn,
  required String key,
}) => db.customStatement(
  'UPDATE $table SET existence_at = COALESCE(deleted_at, created_at) '
  'WHERE $keyColumn = ? AND existence_at IS NULL',
  [key],
);
