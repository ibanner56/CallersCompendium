import 'package:drift/drift.dart';

import 'database.dart';
import 'shareable_text.dart';

/// Raised when a write would give a row a `UNIQUE` natural key that a
/// **different** row already holds — an *edit* renaming onto a live or
/// tombstoned holder ([resolveNaturalKeyCollision]), or a *creation* landing on
/// a live one ([refuseCreationOntoLiveNaturalKey]).
///
/// This is the visible half of issue #1348's ruling. `docs/design/sync-spec.md`
/// §4.1 says a write whose normalised target is occupied must store the value
/// un-normalised rather than fail — but that remedy is only available while the
/// user's own bytes differ from the incumbent's. When they do not, storing the
/// value would violate the `UNIQUE` index, so there is no way to keep the edit;
/// the choice is between refusing it and discarding it. Refusing is the one the
/// user can see and act on, and it is what the four natural-key repositories
/// now do. For a creation the remedy is not merely unavailable but meaningless:
/// a new row has no previous value to keep un-normalised.
///
/// Distinct from the [StateError] those repositories raise for an inbound sync
/// record holding an occupied key (§6.7). That one reports a record to
/// reconciliation and is never shown to anybody; this one is an answer to a
/// person who just typed a name, and the screens that raise it catch it by type
/// to say so.
///
/// [value] is user-entered text. Screens MUST render it as plain text in their
/// own localized sentence and MUST NOT surface [toString], which names internal
/// table and row identifiers (CWE-209).
class DuplicateNaturalKeyError implements Exception {
  const DuplicateNaturalKeyError({
    required this.table,
    required this.column,
    required this.value,
    required this.holderId,
  });

  /// The snake_case table whose `UNIQUE` index refused the value, e.g.
  /// `choreographers`.
  final String table;

  /// The snake_case column carrying that index, e.g. `name`.
  final String column;

  /// The value the user asked for, as it would have been stored.
  final String value;

  /// The id of the row that already holds [value].
  final String holderId;

  @override
  String toString() =>
      'DuplicateNaturalKeyError: $table.$column "$value" is already held by '
      '"$holderId"';
}

/// Decides what an ordinary (non-sync) write to [recordId] does when the
/// normalised form of [incomingValue] is already held by [incumbentId], and
/// returns the value to store when the write may proceed.
///
/// This is the statement of issue #1348's ruling for a write to a row that
/// already exists, and it asks **two** questions rather than one.
/// [refuseCreationOntoLiveNaturalKey] states the same ruling for a creation,
/// which reaches neither question because there is no stored value to compare
/// against:
///
/// 1. *Did the user change the value?* If the stored value and the incoming one
///    derive different targets, the edit is a genuine rename onto a name
///    another row already holds. §4.1's remedy does not apply — there is no
///    un-normalised form of the new value that is not simply the other row's
///    name — so this throws [DuplicateNaturalKeyError] and writes nothing. No
///    skip is recorded: the row is not left un-normalised, so there is nothing
///    to re-attempt, and recording one would pin §4.1's bounded retry open for
///    a collision that no longer exists the moment the user picks another name.
/// 2. *Would the un-normalised form still collide?* If the user typed the
///    incumbent's exact bytes, storing them violates `UNIQUE`. §4.1's carve-out
///    is written for the case where the row's own bytes differ from the
///    incumbent's; where they do not, refusing visibly is the only outcome that
///    is neither a crash nor a silent discard.
///
/// Otherwise this is §4.1's true carve-out — typically a write that leaves the
/// value alone, such as an archive merge re-importing a recorded row, or a tag
/// colour edit. The caller stores the returned value, which is
/// [sanitizeShareableText] of the user's own input rather than its NFC form,
/// and records the row under [address].
///
/// [storedValue] is the row's current stored value, read inside the caller's
/// transaction. Passing the model's value instead would compare the edit
/// against itself and answer question 1 "no" every time.
Future<String> resolveNaturalKeyCollision(
  CompendiumDatabase db, {
  required NormalisationSkipColumn address,
  required String recordId,
  required String storedValue,
  required String incomingValue,
  required String incumbentId,
}) async {
  final target = normalizeShareableText(incomingValue);
  if (normalizeShareableText(storedValue) != target) {
    throw DuplicateNaturalKeyError(
      table: address.table,
      column: address.column,
      value: target,
      holderId: incumbentId,
    );
  }
  final deferred = sanitizeShareableText(incomingValue);
  // Exactly the index's own test: these three tables carry a plain `UNIQUE` on
  // the column, so byte equality is what an insert would fail on. The row
  // itself is excluded because storing its own bytes back is a no-op.
  final occupied = await db
      .customSelect(
        'SELECT id FROM ${address.table} '
        'WHERE ${address.column} = ? AND id != ? LIMIT 1',
        variables: [Variable<String>(deferred), Variable<String>(recordId)],
      )
      .get();
  if (occupied.isNotEmpty) {
    throw DuplicateNaturalKeyError(
      table: address.table,
      column: address.column,
      value: deferred,
      holderId: occupied.single.read<String>('id'),
    );
  }
  return deferred;
}

/// Refuses an ordinary (non-sync) **creation** whose natural key a *live* row
/// already holds, and returns normally when the write may proceed.
///
/// [resolveNaturalKeyCollision] answers the question for an existing row. It is
/// never consulted for a creation, because `collidingEdit` requires the row to
/// be there already — so until this existed, a creation carrying a fresh id fell
/// through to the insert. That was not a takeover: drift emits
/// `ON CONFLICT("<primary key>") DO UPDATE`, so a conflict on the *natural* key
/// is outside the clause's target and SQLite refuses the statement. But it
/// refused it as a raw `SqliteException`, which nothing on a user's path catches
/// by type, so the action failed while telling the user nothing.
///
/// Refusing here is the same ruling #1348 settled for a rename, applied one case
/// earlier: §4.1's store-un-normalised remedy has nothing to offer a creation —
/// there is no previous value for the new row to keep — so the choice is between
/// refusing visibly and failing opaquely.
///
/// **[incumbentDeletedAt] is what the whole decision turns on.** A *tombstoned*
/// holder must NOT be refused: [adoptTombstonedNaturalKey] reconciles that case
/// on purpose, and refusing it would break re-creating a deleted tag under its
/// old name — the very regression adoption exists to fix. Only a live holder is
/// a duplicate.
///
/// Callers must gate this on `fromSync == false`. §6.7 owns identity for an
/// inbound record and reports it to reconciliation with a [StateError] that is
/// never shown to anybody; this error is an answer to a person.
void refuseCreationOntoLiveNaturalKey({
  required NormalisationSkipColumn address,
  required String normalisedValue,
  required String incumbentId,
  required DateTime? incumbentDeletedAt,
}) {
  if (incumbentDeletedAt != null) return;
  throw DuplicateNaturalKeyError(
    table: address.table,
    column: address.column,
    value: normalisedValue,
    holderId: incumbentId,
  );
}
