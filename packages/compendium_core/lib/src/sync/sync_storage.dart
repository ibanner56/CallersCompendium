import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../model/choreographer.dart';
import '../model/figure_source.dart';
import '../model/tunes_source.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/provenance.dart';
import '../model/published_source.dart';
import '../model/program.dart';
import '../model/tag.dart';
import '../model/venue.dart';
import '../imports/dedupe.dart';
import '../privacy/data_classification.dart';
import '../privacy/settings_registry.dart';
import '../serialization/archive_entity_codec.dart';
import '../sync/canonical_json.dart';
import '../storage/database.dart';
import '../storage/existence.dart';
import '../storage/repositories/repositories.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/sync_local_repository.dart';
import '../storage/shareable_text.dart';
import 'sync_apply.dart';
import 'sync_admission.dart';
import 'sync_codec.dart';
import 'sync_id.dart';
import 'sync_merge.dart';
import 'sync_quarantine.dart' show syncRecordReferences;
import 'sync_record_kind.dart';
import 'sync_reconciliation.dart';
import 'sync_report.dart';
import 'sync_review.dart';

Iterable<List<T>> _chunked<T>(Iterable<T> values, int size) sync* {
  final list = values.toList(growable: false);
  for (var start = 0; start < list.length; start += size) {
    final end = start + size < list.length ? start + size : list.length;
    yield list.sublist(start, end);
  }
}

Future<List<T>> _queryInChunks<T>(
  Iterable<String> ids,
  Future<List<T>> Function(List<String> chunk) query,
) async {
  final rows = <T>[];
  for (final chunk in _chunked(ids, 500)) {
    rows.addAll(await query(chunk));
  }
  return rows;
}

typedef _NaturalKeyAddress = ({SyncRecordKind kind, String key});
typedef _NaturalKeyValue = ({
  String id,
  String? type,
  bool deleted,
  bool? shareable,
});

final class _NaturalKeyIndex {
  _NaturalKeyIndex(this._rows);

  final Map<_NaturalKeyAddress, _NaturalKeyValue> _rows;

  _NaturalKeyValue? lookup(SyncRecordKind kind, String key) =>
      _rows[(kind: kind, key: key)];

  void removeId(SyncRecordKind kind, String id) {
    _rows.removeWhere(
      (address, value) => address.kind == kind && value.id == id,
    );
  }

  void add({
    required SyncRecordKind kind,
    required String key,
    required _NaturalKeyValue value,
  }) {
    final address = (kind: kind, key: key);
    final current = _rows[address];
    if (current == null || _prefer(value, current)) {
      _rows[address] = value;
    }
  }

  void replace({
    required SyncRecordKind kind,
    required String id,
    required String key,
    required String? type,
    required bool deleted,
    required bool? shareable,
  }) {
    removeId(kind, id);
    add(
      kind: kind,
      key: key,
      value: (id: id, type: type, deleted: deleted, shareable: shareable),
    );
  }

  static bool _prefer(_NaturalKeyValue candidate, _NaturalKeyValue current) {
    if (candidate.deleted != current.deleted) return !candidate.deleted;
    if (candidate.shareable != current.shareable) {
      return candidate.shareable == false;
    }
    return candidate.id.compareTo(current.id) < 0;
  }
}

/// A complete local sync snapshot owned by the repository/database boundary.
class SyncStorageSnapshot {
  const SyncStorageSnapshot({
    required this.epoch,
    required this.previouslyUsed,
    required this.local,
    required this.baseline,
    Map<SyncRecordAddress, SyncMergeCandidate?>? publication,
    Map<SyncRecordAddress, SyncMergeCandidate?>? pendingLive,
    this.pending = const {},
    this.withheld = const [],
  }) : publication = publication ?? local,
       pendingLive = pendingLive ?? const {};

  final String? epoch;
  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;

  /// The manifest view. Pending tombstones overlay live rows here without
  /// changing the live merge view until their citation is gone.
  final Map<SyncRecordAddress, SyncMergeCandidate?> publication;

  /// The captured live rows underneath pending tombstones. These rows stay out
  /// of [local] but still participate in optimistic-concurrency checks.
  final Map<SyncRecordAddress, SyncMergeCandidate?> pendingLive;

  /// Addresses held in [pendingDeletions], excluded from merge and baseline
  /// advancement while their local citations still exist.
  final Set<SyncRecordAddress> pending;

  /// Records this snapshot withheld from publication because this device could
  /// not decode their stored content (spec §6.9, #1347).
  ///
  /// Carried on the snapshot rather than emitted through a sink passed down
  /// into storage: the coordinator owns the per-pass [SyncReportSink], and the
  /// return-carried shape is the one this boundary already uses for
  /// [SyncFreshAttachDedupeResult.reports]. Threading the sink the other way
  /// would put pass-scoped state on a storage object that is otherwise free of
  /// it, and would change four interface signatures to do it.
  ///
  /// Empty for every library with no undecodable row, which is every library
  /// this has ever been observed on — the reports exist so the one that does
  /// have such a row is not silently short a dance.
  final List<SyncReport> withheld;
}

/// The parent row of a two-phase record as it stood before its inbound write.
///
/// A `null` companion means the record had no row then, so the undo is a
/// delete rather than a rewrite.
final class _ParentPreImage {
  const _ParentPreImage({this.dance, this.program});

  final DancesCompanion? dance;
  final ProgramsCompanion? program;
}

final class _InboundDependentIndex {
  final Map<String, List<SyncRecordAddress>> danceLinkOwners = {};
  final Map<String, List<SyncRecordAddress>> programSlotOwners = {};
}

Map<String, Object?> _normalizeInboundTimestampBody({
  required SyncRecordKind kind,
  required Map<String, Object?> body,
  required DateTime updatedAt,
  required DateTime? deletedAt,
}) {
  if (kind != SyncRecordKind.dance && kind != SyncRecordKind.program) {
    return body;
  }
  return Map<String, Object?>.from(body)
    ..['updatedAt'] = updatedAt.toIso8601String()
    ..['deletedAt'] = deletedAt?.toIso8601String();
}

/// The result of scanning or applying the W8 live-dance dedupe pass.
class SyncFreshAttachDedupeResult {
  const SyncFreshAttachDedupeResult({
    required this.duplicateCount,
    required this.reports,
  });

  final int duplicateCount;
  final List<SyncReport> reports;
}

/// The report raised for a dance withheld because this device cannot decode
/// its stored figures or tunes (spec §6.9, #1347).
///
/// One shape for every withhold site on purpose. A single pass reaches more
/// than one of them for the same row — a fresh attach takes a snapshot *and*
/// runs the dedupe plan — and [SyncReport.coalescingKey] folds code, kind,
/// record id and peer id, so identical reports collapse to one notice in the
/// coordinator's sink rather than repeating per path.
///
/// The message names both columns because the withhold does: it is raised for
/// an undecodable `figures_json` or an undecodable `tunes_json`, and a message
/// naming only figures would be false for half the cases — the same
/// shaped-around-the-instance mistake that let a tunes-only row through four
/// figure-shaped guards in #1391.
SyncReport _withheldUnreadableDanceReport(String id) => SyncReport(
  code: SyncReportCode.withheldUnreadableRecord,
  kind: SyncRecordKind.dance,
  recordId: id,
  message:
      'Dance withheld from publication: its stored figures or tunes could not '
      'be decoded, so this device cannot speak for the record.',
);

/// The production storage adapter for the core sync engine.
///
/// Reads use full-fidelity models so a shareable inbound overlay cannot erase
/// device-local fields. Writes use dedicated inbound repository writers so
/// interactive side effects cannot alter the validated peer body, then restore
/// the wire timestamp triple because local persistence stamps causal times.
final class CompendiumSyncStorage
    implements
        SyncApplyReconciliationStorage,
        SyncApplyConcurrencyStorage,
        SyncApplyRestorableStorage {
  CompendiumSyncStorage(this.repositories);

  final CompendiumRepositories repositories;
  final Map<SyncRecordAddress, Object> _deferredEntities = {};
  final Set<SyncRecordAddress> _pendingParentWrites = {};
  Set<SyncRecordAddress> _inboundTombstonedAddresses = {};

  /// Pending deletions this batch's reconciliation carried onto a survivor.
  ///
  /// A remap is not a revival: the inbound record is a different UUID that
  /// shares a natural key, and §6.6 already decided what happens to the
  /// deferred deletion when it migrated the identity. Cancelling it here on
  /// the strength of the inbound stamp would overturn that decision from the
  /// writer, which is not the writer's call.
  final Set<SyncRecordAddress> _remappedPendingDeletions = {};
  _NaturalKeyIndex? _naturalKeyIndex;
  final Expando<_InboundDependentIndex> _dependentIndexCache =
      Expando<_InboundDependentIndex>();

  /// Memoises [_previouslyUsed] per sync identity for this storage instance's
  /// lifetime.
  ///
  /// A fresh [CompendiumSyncStorage] is created per worker pass, so this
  /// memo's lifetime is exactly one pass. `snapshot()` is called several
  /// times per pass (once up front, again after §6.9 repairs, again inside
  /// `buildPublicationState`, ...) and each call previously re-derived the
  /// slow PBKDF2-style verifier for every stored sync identity. Caching the
  /// match result here means only the first check in a pass pays that cost;
  /// [markSyncUsed] writing a new verifier updates the entry directly instead
  /// of leaving it stale.
  final Map<String, bool> _identityVerifierMemo = {};

  CompendiumDatabase get _db => repositories.db;

  /// Whether [syncId] has already completed a publication, deriving the slow
  /// verifier at most once per sync identity for this instance.
  ///
  /// `syncId == null` still loads the stored marker (without deriving
  /// anything) so a legacy fingerprint marker migrates even when the caller
  /// has no identity of its own to check against it.
  Future<bool> _previouslyUsed(String? syncId) async {
    if (syncId != null) {
      final cached = _identityVerifierMemo[syncId];
      if (cached != null) return cached;
    }
    final verifiers = await _loadUsedIdentityVerifiers(syncId);
    if (syncId == null) return false;
    final result = verifiers.any((verifier) => verifier.matches(syncId));
    _identityVerifierMemo[syncId] = result;
    return result;
  }

  Future<SyncStorageSnapshot> snapshot({
    String? syncId,
  }) => repositories.transaction(() async {
    await _revalidatePendingDeletions();
    final previouslyUsed = await _previouslyUsed(syncId);
    final baseline = await repositories.syncLocal.snapshotBaseline();
    final baselineState = await repositories.syncLocal.getBaselineState();
    final local = <SyncRecordAddress, SyncMergeCandidate?>{};
    final withheld = <SyncReport>[];
    final customFields = await repositories.customFieldDefs
        .listAllWithDeleted();
    final allowedCustomFieldIds = {
      for (final entry in customFields)
        if (entry.field.shareable && !entry.deleted) entry.field.id,
    };

    Future<void> addEntity({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
      required DateTime updatedAt,
      required DateTime existenceAt,
      DateTime? deletedAt,
    }) async {
      final blob = syncRecordBlobForEntity(
        kind,
        entity,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        existenceAt: existenceAt,
        allowedCustomFieldIds: allowedCustomFieldIds,
      );
      if (blob == null) return;
      final address = (kind: kind, recordId: id);
      local[address] = SyncMergeCandidate(
        blob: blob,
        wireHash: sha256Hex(encodeSyncRecordBlobUtf8(blob)),
      );
    }

    final dances = await repositories.dances.listAll(includeDeleted: true);
    final danceRows = await _db.select(_db.dances).get();
    final danceRowsById = {for (final row in danceRows) row.id: row};
    for (final dance in dances) {
      final row = danceRowsById[dance.id];
      if (row == null) continue;
      // Withheld exactly as [_readDanceBody] withholds, and this is the path
      // that matters most: it builds `local` and the wire hashes. A body for an
      // undecodable dance would carry the transcription as an empty array
      // beside a `figuresRaw` sibling, which a peer that does not understand
      // the key applies over its own readable copy (#1347). The hash would also
      // fold `figuresRaw` in, which reaches dedupe and merge identity rather
      // than display alone.
      //
      // Consequence, stated rather than implied: an undecodable dance is not
      // published at all. Conservative in the same direction as the withhold —
      // this device does not speak for a row it cannot read.
      //
      // Reported rather than dropped in silence (#1347): the withhold is
      // correct and stays, but a dance that is simply absent from every peer,
      // with nothing said about it, is indistinguishable from one that synced.
      if (dance.figuresSource is UnreadableFigures ||
          dance.tunesSource is UnreadableTunes) {
        withheld.add(_withheldUnreadableDanceReport(dance.id));
        continue;
      }
      await addEntity(
        kind: SyncRecordKind.dance,
        id: dance.id,
        entity: dance,
        updatedAt: row.updatedAt,
        existenceAt: row.existenceAt ?? row.updatedAt,
        deletedAt: row.deletedAt,
      );
    }

    final programs = await repositories.programs.listAll(includeDeleted: true);
    final programRows = await _db.select(_db.programs).get();
    final programRowsById = {for (final row in programRows) row.id: row};
    for (final program in programs) {
      final row = programRowsById[program.id];
      if (row == null) continue;
      await addEntity(
        kind: SyncRecordKind.program,
        id: program.id,
        entity: program,
        updatedAt: row.updatedAt,
        existenceAt: row.existenceAt ?? row.updatedAt,
        deletedAt: row.deletedAt,
      );
    }

    final choreographerRows = await _db.select(_db.choreographers).get();
    for (final row in choreographerRows) {
      await addEntity(
        kind: SyncRecordKind.choreographer,
        id: row.id,
        entity: Choreographer(
          id: row.id,
          name: row.name,
          website: row.website,
          notes: row.notes,
          email: row.email,
          location: row.location,
          deceased: row.deceased,
        ),
        updatedAt:
            row.updatedAt ??
            row.existenceAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        existenceAt:
            row.existenceAt ??
            row.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        deletedAt: row.deletedAt,
      );
    }

    final tagRows = await _db.select(_db.tags).get();
    for (final row in tagRows) {
      await addEntity(
        kind: SyncRecordKind.tag,
        id: row.id,
        entity: Tag(id: row.id, name: row.name, color: row.color),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final sourceRows = await _db.select(_db.publishedSources).get();
    for (final row in sourceRows) {
      await addEntity(
        kind: SyncRecordKind.publishedSource,
        id: row.id,
        entity: PublishedSource(
          id: row.id,
          title: row.title,
          author: row.author,
          year: row.year,
          url: row.url,
          notes: row.notes,
        ),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    for (final entry in customFields) {
      final row = await (_db.select(
        _db.customFieldDefs,
      )..where((table) => table.id.equals(entry.field.id))).getSingleOrNull();
      if (row == null) continue;
      await addEntity(
        kind: SyncRecordKind.customFieldDef,
        id: entry.field.id,
        entity: entry.field,
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final difficultyRows = await _db.select(_db.difficultyLevels).get();
    for (final row in difficultyRows) {
      await addEntity(
        kind: SyncRecordKind.difficultyLevel,
        id: row.id,
        entity: DifficultyLevel(
          id: row.id,
          label: row.label,
          position: row.position,
        ),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final venueRows = await _db.select(_db.venues).get();
    for (final row in venueRows) {
      final provenance = await _venueProvenance(row.id);
      await addEntity(
        kind: SyncRecordKind.venue,
        id: row.id,
        entity: Venue(
          id: row.id,
          name: row.name,
          address1: row.address1,
          address2: row.address2,
          city: row.city,
          stateProv: row.stateProv,
          country: row.country,
          postalCode: row.postalCode,
          plus4: row.plus4,
          website: row.website,
          sponsor: row.sponsor,
          eventName: row.eventName,
          time: row.time,
          genericSchedule: row.genericSchedule,
          price: row.price,
          notes: row.notes,
          contact1Name: row.contact1Name,
          contact1Phone: row.contact1Phone,
          contact1Email: row.contact1Email,
          contact2Name: row.contact2Name,
          contact2Phone: row.contact2Phone,
          contact2Email: row.contact2Email,
          provenance: provenance,
        ),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final settingRows = await _db.select(_db.settings).get();
    for (final row in settingRows) {
      if (classifySettingsKey(row.key)?.egress != EgressClass.shareable) {
        continue;
      }
      final blob = SyncSettingsRecord(
        key: row.key,
        value: jsonDecode(row.valueJson),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        deletedAt: row.deletedAt,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
      ).toBlob();
      if (blob == null) continue;
      final address = (kind: SyncRecordKind.setting, recordId: row.key);
      local[address] = SyncMergeCandidate(
        blob: blob,
        wireHash: sha256Hex(encodeSyncRecordBlobUtf8(blob)),
      );
    }

    final publication = <SyncRecordAddress, SyncMergeCandidate?>{...local};
    final pendingLive = <SyncRecordAddress, SyncMergeCandidate?>{};
    final pendingAddresses = <SyncRecordAddress>{};
    final pendingRows = await repositories.syncLocal.listPendingDeletions();
    for (final row in pendingRows) {
      final blob = decodeSyncRecordBlob(row.tombstoneBlob);
      final hash = sha256Hex(encodeSyncRecordBlobUtf8(blob));
      if (blob.kind != row.kind ||
          blob.id != row.recordId ||
          hash != row.tombstoneHash ||
          blob.deletedAt == null) {
        throw StateError(
          'pending tombstone does not match its stored identity or hash',
        );
      }
      final address = (kind: row.kind, recordId: row.recordId);
      pendingLive[address] = local[address];
      local.remove(address);
      final publicationBody = _normalizeInboundTimestampBody(
        kind: blob.kind,
        body: blob.body,
        updatedAt: blob.updatedAt,
        deletedAt: blob.deletedAt,
      );
      final publicationBlob = identical(publicationBody, blob.body)
          ? blob
          : SyncRecordBlob(
              v: blob.v,
              kind: blob.kind,
              id: blob.id,
              updatedAt: blob.updatedAt,
              deletedAt: blob.deletedAt,
              existenceAt: blob.existenceAt,
              body: publicationBody,
            );
      publication[address] = SyncMergeCandidate(
        blob: publicationBlob,
        wireHash: sha256Hex(encodeSyncRecordBlobUtf8(publicationBlob)),
      );
      pendingAddresses.add(address);
    }

    await _applySyncExcludeImports(publication);

    return SyncStorageSnapshot(
      epoch: baselineState?.epoch,
      previouslyUsed: previouslyUsed,
      local: local,
      baseline: baseline,
      publication: publication,
      pendingLive: pendingLive,
      pending: pendingAddresses,
      withheld: List.unmodifiable(withheld),
    );
  });

  /// Applies the per-device `sync_exclude_imports` upload-budget filter (spec
  /// §6.1) to a fully built publication candidate map, in place.
  ///
  /// Scope is exactly "a dance carrying import provenance that nothing
  /// surviving this filter cites, directly or transitively" — provenance
  /// alone decides eligibility, but survival is a forward reachability walk
  /// from every record that is published independently of this filter (any
  /// non-imported dance, program, or other kind) across citation edges
  /// (citer → citee), so a program (or another dance's link) that cites an
  /// imported dance keeps it published, and that imported dance's own
  /// citations of further imported dances keep those published too. This is
  /// the §6.9 withholding fixpoint run in reverse, and in the opposite
  /// direction of [syncQuarantineClosure] (which walks dependents of a
  /// blocked root; this walks references reachable from a kept root): an
  /// imported-only citation cycle with no citer outside it is withheld in
  /// full, never partially retained, because none of its members is ever
  /// reached from a root.
  ///
  /// A tombstone is never withheld by this filter regardless of provenance:
  /// deletion is not an upload-budget decision, and soft deletion leaves the
  /// dance's provenance row in place, so excluding tombstones here would
  /// silently drop a previously published imported dance's deletion from the
  /// manifest and leave peers holding the live record forever.
  ///
  /// Upload-only: [local] (used for merge comparison against inbound peer
  /// data) is never touched here, so a peer's imported dance is still applied
  /// on this device regardless of this setting (spec: "governs upload only").
  /// Withheld entries are set to `null` rather than removed, matching how
  /// [planSyncPublication] already treats an address with no candidate.
  Future<void> _applySyncExcludeImports(
    Map<SyncRecordAddress, SyncMergeCandidate?> publication,
  ) async {
    if (await repositories.settings.get(syncExcludeImportsKey) != true) {
      return;
    }
    final provenanceRows = await _db.select(_db.provenance).get();
    if (provenanceRows.isEmpty) return;

    final imported = <SyncRecordAddress>{
      for (final row in provenanceRows)
        (kind: SyncRecordKind.dance, recordId: row.danceId),
    };
    final withholdable = <SyncRecordAddress>{
      for (final address in imported)
        if (publication[address] != null &&
            publication[address]!.blob.deletedAt == null)
          address,
    };
    if (withholdable.isEmpty) return;

    final reached = <SyncRecordAddress>{
      for (final entry in publication.entries)
        if (entry.value != null && !withholdable.contains(entry.key)) entry.key,
    };
    final pending = <SyncRecordAddress>[...reached];
    for (var index = 0; index < pending.length; index++) {
      final candidate = publication[pending[index]];
      if (candidate == null) continue;
      for (final reference in syncRecordReferences(candidate)) {
        if (reached.add(reference)) {
          pending.add(reference);
        }
      }
    }

    for (final address in withholdable) {
      if (!reached.contains(address)) {
        publication[address] = null;
      }
    }
  }

  /// Scans the current live dance collection for W8 title/choreography
  /// matches and applies the complete merge and identity rewrite inside the
  /// same repository transaction as the resulting rows.
  ///
  /// This full-library scan is a fresh-attach operation. Ordinary passes use
  /// [refreshDanceAmbiguityReviews] so they do not rediscover or merge dances.
  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach() =>
      repositories.transaction(() async {
        final withheld = <SyncReport>[];
        final plan = await _danceDedupePlan(withheld: withheld);
        await _refreshDanceAmbiguityReviews(plan.ambiguities);
        final reports = [
          ...withheld,
          ..._reportsForDanceAmbiguities(plan.ambiguities),
        ];

        if (plan.merges.isEmpty) {
          return SyncFreshAttachDedupeResult(
            duplicateCount: 0,
            reports: List.unmodifiable(reports),
          );
        }
        for (final merge in plan.merges) {
          await _applyDanceDedupeMerge(merge, plan.aliases);
        }
        await rebuildDerivedIndexes();
        return SyncFreshAttachDedupeResult(
          duplicateCount: plan.merges.fold<int>(
            0,
            (count, merge) => count + merge.losingIds.length,
          ),
          reports: List.unmodifiable(reports),
        );
      });

  /// Revalidates only the dance ambiguity pairs already present in the review
  /// queue. It deliberately does not scan the complete dance collection or
  /// discover new same-title pairs during steady-state sync.
  Future<SyncFreshAttachDedupeResult> refreshDanceAmbiguityReviews() =>
      repositories.transaction(() async {
        final queuedRows = (await repositories.syncLocal.listReviewQueue())
            .where(
              (row) =>
                  row.kind == SyncRecordKind.dance &&
                  row.reason == syncDanceChoreographyAmbiguityReason,
            );
        final pendingDanceIds = {
          for (final pending
              in await repositories.syncLocal.listPendingDeletions())
            if (pending.kind == SyncRecordKind.dance) pending.recordId,
        };
        final ambiguities = <SyncDanceDedupeAmbiguity>[];
        final seenPairs = <String>{};
        final withheld = <SyncReport>[];
        for (final row in queuedRows) {
          final pairKey = _danceReviewPairKey(row.recordId, row.counterpartId);
          if (!seenPairs.add(pairKey) ||
              row.recordId == row.counterpartId ||
              pendingDanceIds.contains(row.recordId) ||
              pendingDanceIds.contains(row.counterpartId)) {
            continue;
          }
          final left = await _danceCandidate(row.recordId, withheld: withheld);
          final right = await _danceCandidate(
            row.counterpartId,
            withheld: withheld,
          );
          if (left == null || right == null) continue;
          final pairPlan = planFreshAttachDedupe([left, right]);
          if (pairPlan.ambiguities.length == 1) {
            ambiguities.add(pairPlan.ambiguities.single);
          }
        }
        await _refreshDanceAmbiguityReviews(ambiguities);
        return SyncFreshAttachDedupeResult(
          duplicateCount: 0,
          reports: List.unmodifiable([
            ...withheld,
            ..._reportsForDanceAmbiguities(ambiguities),
          ]),
        );
      });

  List<SyncReport> _reportsForDanceAmbiguities(
    Iterable<SyncDanceDedupeAmbiguity> ambiguities,
  ) => [
    for (final ambiguity in ambiguities)
      if (ambiguity.left.blob.updatedAt == ambiguity.right.blob.updatedAt)
        SyncReport(
          code: SyncReportCode.equalUpdatedAt,
          kind: SyncRecordKind.dance,
          recordId: ambiguity.firstId,
          message:
              'Dances with the same normalized title have different '
              'choreography at the same updatedAt; no silent winner was '
              'selected.',
        ),
  ];

  Future<void> _refreshDanceAmbiguityReviews(
    Iterable<SyncDanceDedupeAmbiguity> ambiguities,
  ) async {
    final expected = <String, SyncDanceDedupeAmbiguity>{
      for (final ambiguity in ambiguities)
        _danceReviewPairKey(ambiguity.firstId, ambiguity.secondId): ambiguity,
    };
    final existingRows = await repositories.syncLocal.listReviewQueue();
    for (final row in existingRows) {
      if (row.kind != SyncRecordKind.dance ||
          row.reason != syncDanceChoreographyAmbiguityReason) {
        continue;
      }
      final ambiguity =
          expected[_danceReviewPairKey(row.recordId, row.counterpartId)];
      if (ambiguity == null ||
          row.recordId != ambiguity.firstId ||
          row.counterpartId != ambiguity.secondId ||
          row.candidateHash != ambiguity.candidate.wireHash) {
        await repositories.syncLocal.deleteReview(
          kind: row.kind,
          recordId: row.recordId,
          counterpartId: row.counterpartId,
        );
      }
    }

    final queuedAt = DateTime.now().toUtc();
    for (final ambiguity in expected.values) {
      final candidate = ambiguity.candidate;
      final candidateBlob = encodeSyncRecordBlob(candidate.blob);
      final existing = await repositories.syncLocal.getReviewQueue(
        kind: SyncRecordKind.dance,
        recordId: ambiguity.firstId,
        counterpartId: ambiguity.secondId,
      );
      final local = ambiguity.left.blob.id == ambiguity.firstId
          ? ambiguity.left
          : ambiguity.right;
      // The local hash is part of what makes a row current: resolution refuses
      // a decision whose local record moved after enqueue, so a row kept with
      // a stale hash would stay actionable and never be resolvable.
      if (existing != null &&
          existing.candidateHash == candidate.wireHash &&
          existing.candidateBlob == candidateBlob &&
          existing.localHash == local.wireHash) {
        continue;
      }
      if (existing != null) {
        await repositories.syncLocal.deleteReview(
          kind: SyncRecordKind.dance,
          recordId: ambiguity.firstId,
          counterpartId: ambiguity.secondId,
        );
      }
      await repositories.syncLocal.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: ambiguity.firstId,
        counterpartId: ambiguity.secondId,
        reason: syncDanceChoreographyAmbiguityReason,
        candidateBlob: candidateBlob,
        candidateHash: candidate.wireHash,
        localHash: local.wireHash,
        queuedAt: queuedAt,
      );
    }
  }

  String _danceReviewPairKey(String left, String right) {
    final first = left.compareTo(right) <= 0 ? left : right;
    final second = first == left ? right : left;
    return canonicalJson([first, second]);
  }

  /// [withheld] collects a report per dance this plan refuses to consider
  /// because its stored content cannot be decoded (#1347). It is an out
  /// parameter rather than part of the returned plan because
  /// [SyncFreshAttachDedupePlan] is the pure planner's own type, shared with
  /// callers that have no library behind them.
  Future<SyncFreshAttachDedupePlan> _danceDedupePlan({
    required List<SyncReport> withheld,
  }) async {
    final customFields = await repositories.customFieldDefs
        .listAllWithDeleted();
    final allowedCustomFieldIds = {
      for (final entry in customFields)
        if (entry.field.shareable && !entry.deleted) entry.field.id,
    };
    final dances = await repositories.dances.listAll(includeDeleted: true);
    final rows = await _db.select(_db.dances).get();
    final rowsById = {for (final row in rows) row.id: row};
    final pendingDanceIds = {
      for (final pending in await repositories.syncLocal.listPendingDeletions())
        if (pending.kind == SyncRecordKind.dance) pending.recordId,
    };
    final candidates = <SyncMergeCandidate>[];
    for (final dance in dances) {
      // The live row is only retained until its inbound tombstone can apply.
      // It must not become a fresh-attach survivor or merge target.
      if (pendingDanceIds.contains(dance.id)) continue;
      // Withheld for the same reason [_readDanceBody] withholds: this device
      // cannot read the row it would be speaking for, and the body it would build
      // carries the transcription as an empty array beside a `figuresRaw` sibling.
      // A peer that does not understand `figuresRaw` applies the empty array over
      // its own readable copy (#1347).
      //
      // These two paths do not go through [_readDanceBody], so they are not
      // covered by its guard, and they became reachable only because this change
      // made `listAll`/`getById` return such a dance instead of raising.
      //
      // Consequence, stated rather than implied: an undecodable dance is not
      // offered as a dedupe match on a fresh attach, and says so (#1347).
      if (dance.figuresSource is UnreadableFigures ||
          dance.tunesSource is UnreadableTunes) {
        withheld.add(_withheldUnreadableDanceReport(dance.id));
        continue;
      }
      final row = rowsById[dance.id];
      if (row == null) continue;
      final blob = syncRecordBlobForEntity(
        SyncRecordKind.dance,
        dance,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
        existenceAt: row.existenceAt ?? row.updatedAt,
        allowedCustomFieldIds: allowedCustomFieldIds,
      );
      if (blob != null) candidates.add(SyncMergeCandidate(blob: blob));
    }
    return planFreshAttachDedupe(candidates);
  }

  Future<void> _applyDanceDedupeMerge(
    SyncDanceDedupeMerge merge,
    Map<String, String> aliases,
  ) async {
    final loserDeviceLocalCustomFields = <CustomFieldValue>[];
    for (final losingId in merge.losingIds) {
      loserDeviceLocalCustomFields.addAll(
        await repositories.dances.readDeviceLocalCustomFields(losingId),
      );
    }
    final body = _rewriteDanceReferences(merge.winner.blob.body, aliases);
    final record = SyncApplyRecord(
      address: merge.winner.address,
      body: body,
      updatedAt: merge.winner.blob.updatedAt,
      deletedAt: null,
      existenceAt: merge.winner.blob.existenceAt,
      sourceBlob: merge.winner.blob,
    );
    for (final losingId in merge.losingIds) {
      await _rewriteLocalReferences(
        SyncRecordKind.dance,
        losingId,
        merge.winner.blob.id,
      );
      await _remapPendingDeletions(
        kind: SyncRecordKind.dance,
        losingId: losingId,
        survivingId: merge.winner.blob.id,
        aliases: {SyncRecordKind.dance: aliases},
      );
      await repositories.syncLocal.remapIdentity(
        kind: SyncRecordKind.dance,
        losingId: losingId,
        survivingId: merge.winner.blob.id,
      );
    }
    for (final losingId in merge.losingIds) {
      await (_db.delete(
        _db.dances,
      )..where((table) => table.id.equals(losingId))).go();
    }
    final entity = _decodeEntity(record.address.kind, record.body) as Dance;
    await repositories.dances.writeFromSync(
      entity,
      rebuildDerived: false,
      additionalDeviceLocalCustomFields: loserDeviceLocalCustomFields,
    );
    await _restoreTimestamps(
      kind: record.address.kind,
      id: record.address.recordId,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      existenceAt: record.existenceAt,
    );
    await _reconcileDanceReviewQueue(
      survivorId: merge.winner.blob.id,
      losingIds: merge.losingIds.toSet(),
    );
  }

  Future<void> _reconcileDanceReviewQueue({
    required String survivorId,
    required Set<String> losingIds,
  }) async {
    final affectedIds = {...losingIds, survivorId};
    final rows =
        (await repositories.syncLocal.listReviewQueue())
            .where(
              (row) =>
                  row.kind == SyncRecordKind.dance &&
                  row.reason == syncDanceChoreographyAmbiguityReason &&
                  (affectedIds.contains(row.recordId) ||
                      affectedIds.contains(row.counterpartId)),
            )
            .toList()
          ..sort((left, right) {
            final queued = left.queuedAt.compareTo(right.queuedAt);
            if (queued != 0) return queued;
            final record = left.recordId.compareTo(right.recordId);
            if (record != 0) return record;
            return left.counterpartId.compareTo(right.counterpartId);
          });
    final retainedPairs = <String>{};
    for (final row in rows) {
      final mappedRecordId = row.recordId;
      final mappedCounterpartId = row.counterpartId;
      final recordId = losingIds.contains(mappedRecordId)
          ? survivorId
          : mappedRecordId;
      final counterpartId = losingIds.contains(mappedCounterpartId)
          ? survivorId
          : mappedCounterpartId;

      await repositories.syncLocal.deleteReview(
        kind: row.kind,
        recordId: row.recordId,
        counterpartId: row.counterpartId,
      );
      if (recordId == counterpartId) continue;

      final leftId = recordId.compareTo(counterpartId) < 0
          ? recordId
          : counterpartId;
      final rightId = leftId == recordId ? counterpartId : recordId;
      final pairKey = _danceReviewPairKey(leftId, rightId);
      if (retainedPairs.contains(pairKey)) continue;

      final left = await _danceCandidate(leftId);
      final right = await _danceCandidate(rightId);
      if (left == null ||
          right == null ||
          left.blob.deletedAt != null ||
          right.blob.deletedAt != null) {
        continue;
      }
      final plan = planFreshAttachDedupe([left, right]);
      if (plan.ambiguities.length != 1) continue;

      retainedPairs.add(pairKey);
      await repositories.syncLocal.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: leftId,
        counterpartId: rightId,
        reason: syncDanceChoreographyAmbiguityReason,
        candidateBlob: encodeSyncRecordBlob(right.blob),
        candidateHash: right.wireHash,
        localHash: left.wireHash,
        queuedAt: row.queuedAt,
      );
    }
  }

  Map<String, Object?> _rewriteDanceReferences(
    Map<String, Object?> body,
    Map<String, String> aliases,
  ) {
    final copy = Map<String, Object?>.from(body);
    final links = copy['links'];
    if (links is List) {
      final rewritten = <Object?>[];
      final survivorId = copy['id'];
      for (final value in links) {
        if (value is! Map) {
          rewritten.add(value);
          continue;
        }
        final item = Map<String, Object?>.from(value);
        final target = item['targetDanceId'];
        if (target is String) {
          final resolvedTarget = _resolveDanceAlias(target, aliases);
          if (resolvedTarget == survivorId) continue;
          item['targetDanceId'] = resolvedTarget;
        }
        rewritten.add(item);
      }
      copy['links'] = rewritten;
    }
    return copy;
  }

  String _resolveDanceAlias(String id, Map<String, String> aliases) {
    var current = id;
    final seen = <String>{id};
    while (aliases[current] != null && seen.add(aliases[current]!)) {
      current = aliases[current]!;
    }
    return current;
  }

  /// Revalidates pending tombstones against the complete current library.
  ///
  /// Archive merge restores must not use only the archive's written records:
  /// untouched local rows can still cite a pending record.
  Future<void> revalidatePendingDeletions({bool dropMissing = false}) =>
      repositories.transaction(
        () => revalidatePendingDeletionsInTransaction(dropMissing: dropMissing),
      );

  /// Revalidates pending tombstones within an already-open repository
  /// transaction. The caller owns the transaction boundary.
  Future<void> revalidatePendingDeletionsInTransaction({
    bool dropMissing = false,
  }) => _revalidatePendingDeletions(dropMissing: dropMissing);

  /// Applies pending tombstones whose final local citation disappeared.
  ///
  /// This runs before every snapshot so a citation removed by an ordinary
  /// repository transaction is observed by the next pass without requiring a
  /// separate sync trigger.
  Future<void> _revalidatePendingDeletions({bool dropMissing = false}) async {
    final rows = await repositories.syncLocal.listPendingDeletions();
    for (final row in rows) {
      if (await _hasCitation(row.kind, row.recordId)) continue;
      final blob = decodeSyncRecordBlob(row.tombstoneBlob);
      if (blob.kind != row.kind ||
          blob.id != row.recordId ||
          blob.deletedAt == null ||
          sha256Hex(encodeSyncRecordBlobUtf8(blob)) != row.tombstoneHash) {
        throw StateError(
          'pending tombstone does not match its stored identity or hash',
        );
      }
      final current = await read((kind: blob.kind, recordId: blob.id));
      if (current == null && dropMissing) {
        await repositories.syncLocal.deletePendingDeletion(
          kind: row.kind,
          recordId: row.recordId,
        );
        continue;
      }
      final body = _overlay(
        Map<String, Object?>.from(current ?? const {}),
        blob.body,
      );
      final record = SyncApplyRecord(
        address: (kind: blob.kind, recordId: blob.id),
        body: body,
        updatedAt: blob.updatedAt,
        deletedAt: blob.deletedAt,
        existenceAt: blob.existenceAt,
        sourceBlob: blob,
      );
      await writeWithReport(record);
      await repositories.syncLocal.deletePendingDeletion(
        kind: row.kind,
        recordId: row.recordId,
      );
    }
  }

  Map<String, Object?> _overlay(
    Map<String, Object?> current,
    Map<String, Object?> incoming,
  ) {
    for (final entry in incoming.entries) {
      final value = entry.value;
      final previous = current[entry.key];
      if (value is Map && previous is Map) {
        current[entry.key] = _overlay(
          Map<String, Object?>.from(previous),
          Map<String, Object?>.from(value),
        );
      } else {
        current[entry.key] = value;
      }
    }
    return current;
  }

  Future<bool> _hasCitation(
    SyncRecordKind kind,
    String recordId, {
    bool ignoreInboundTombstones = false,
  }) async {
    Future<bool> ownerRemainsLive(
      SyncRecordKind ownerKind,
      String ownerId,
    ) async {
      if (ignoreInboundTombstones &&
          _inboundTombstonedAddresses.contains((
            kind: ownerKind,
            recordId: ownerId,
          ))) {
        return false;
      }
      switch (ownerKind) {
        case SyncRecordKind.dance:
          final row = await (_db.select(
            _db.dances,
          )..where((table) => table.id.equals(ownerId))).getSingleOrNull();
          return row != null && row.deletedAt == null;
        case SyncRecordKind.program:
          final row = await (_db.select(
            _db.programs,
          )..where((table) => table.id.equals(ownerId))).getSingleOrNull();
          return row != null && row.deletedAt == null;
        case SyncRecordKind.choreographer:
        case SyncRecordKind.tag:
        case SyncRecordKind.publishedSource:
        case SyncRecordKind.customFieldDef:
        case SyncRecordKind.difficultyLevel:
        case SyncRecordKind.venue:
        case SyncRecordKind.setting:
          return false;
      }
    }

    switch (kind) {
      case SyncRecordKind.choreographer:
        final rows = await (_db.select(
          _db.danceAuthors,
        )..where((row) => row.choreographerId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.tag:
        final rows = await (_db.select(
          _db.danceTags,
        )..where((row) => row.tagId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.publishedSource:
        final rows = await (_db.select(
          _db.danceSources,
        )..where((row) => row.sourceId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.customFieldDef:
        final rows = await (_db.select(
          _db.customFieldValues,
        )..where((row) => row.fieldId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.difficultyLevel:
        final rows = await (_db.select(
          _db.dances,
        )..where((row) => row.levelId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.id)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.venue:
        final rows = await (_db.select(
          _db.programs,
        )..where((row) => row.venueId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.program, row.id)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.dance:
        final slots = await (_db.select(
          _db.programSlots,
        )..where((row) => row.danceId.equals(recordId))).get();
        for (final row in slots) {
          if (await ownerRemainsLive(SyncRecordKind.program, row.programId)) {
            return true;
          }
        }
        final links = await (_db.select(
          _db.danceLinks,
        )..where((row) => row.targetDanceId.equals(recordId))).get();
        for (final row in links) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.program:
      case SyncRecordKind.setting:
        return false;
    }
  }

  Future<void> markSyncUsed(String syncId) async {
    if (await _previouslyUsed(syncId)) return;
    final verifiers = await _loadUsedIdentityVerifiers(syncId);
    final next = [...verifiers, _StoredSyncIdentityVerifier.create(syncId)];
    final encoded = next.map((verifier) => verifier.toJson()).toList()
      ..sort(
        (left, right) => (left['verifier']! as String).compareTo(
          right['verifier']! as String,
        ),
      );
    await repositories.settings.set(syncLastUsedFingerprintKey, encoded);
    // The marker just gained this identity's verifier: update the memo
    // directly rather than dropping it, so a `snapshot()` later in the same
    // pass sees `previouslyUsed: true` without re-deriving.
    _identityVerifierMemo[syncId] = true;
  }

  /// Atomically records the manifest attempt and marks the sync identity
  /// immediately before the manifest request. Keep this after blob publication
  /// so a failed upload does not mark the sync identity used.
  ///
  /// The verifier is deliberately conservative: once a manifest is prepared,
  /// a later crash or network failure must still require replacement
  /// confirmation if the server accepted that publication.
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  }) => repositories.transaction(() async {
    await repositories.syncLocal.markPublishedAll(records);
    await markSyncUsed(syncId);
  });

  Future<List<_StoredSyncIdentityVerifier>> _loadUsedIdentityVerifiers(
    String? syncId,
  ) async {
    final marker = await repositories.settings.get(syncLastUsedFingerprintKey);
    final verifiers = _decodeUsedIdentityVerifiers(marker);
    final legacyFingerprints = _decodeLegacyIdentityFingerprints(marker);
    if (legacyFingerprints.isEmpty) return verifiers;

    final migrated = [...verifiers];
    if (syncId != null &&
        legacyFingerprints.contains(_legacyIdentityFingerprint(syncId))) {
      migrated.add(_StoredSyncIdentityVerifier.create(syncId));
    }
    await repositories.settings.set(
      syncLastUsedFingerprintKey,
      migrated.map((verifier) => verifier.toJson()).toList(),
    );
    return migrated;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      repositories.transaction(action);

  /// Resolves persisted W8 choreography and W14 tombstone review decisions.
  ///
  /// The queue row is re-read inside the transaction so a stale screen cannot
  /// clear a replacement candidate. New actionable rows carry the local
  /// wire-hash captured at enqueue; legacy rows without that value fail closed
  /// because their original local version is unknowable.
  Future<void> resolveReviewQueue({
    required ReviewQueueRow expectedRow,
    required SyncReviewAction action,
    String? newNaturalKey,
  }) => repositories.transaction(() async {
    final currentRow = await repositories.syncLocal.getReviewQueue(
      kind: expectedRow.kind,
      recordId: expectedRow.recordId,
      counterpartId: expectedRow.counterpartId,
    );
    if (currentRow == null || !_sameReviewQueueRow(currentRow, expectedRow)) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    if (currentRow.reason == syncDanceChoreographyAmbiguityReason) {
      await _resolveDanceAmbiguity(
        currentRow: currentRow,
        action: action,
        newNaturalKey: newNaturalKey,
      );
      return;
    }
    if (syncNaturalKeyRenameCollisionReasons.contains(currentRow.reason)) {
      await _resolveNaturalKeyRenameCollision(
        currentRow: currentRow,
        action: action,
        newNaturalKey: newNaturalKey,
      );
      return;
    }
    if (currentRow.reason != syncBaselineAbsenceTombstoneReason) {
      throw const SyncReviewException(SyncReviewFailureCode.unsupportedReason);
    }
    final SyncRecordBlob candidate;
    try {
      candidate = decodeSyncRecordBlob(currentRow.candidateBlob);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    if (currentRow.candidateHash !=
            sha256Hex(encodeSyncRecordBlobUtf8(candidate)) ||
        currentRow.candidateHash != expectedRow.candidateHash ||
        candidate.kind != currentRow.kind ||
        candidate.id != currentRow.counterpartId ||
        candidate.body['id'] != candidate.id ||
        candidate.deletedAt == null ||
        currentRow.recordId == candidate.id ||
        !syncNaturalKeyKinds.contains(candidate.kind) ||
        syncNaturalKeyForBody(candidate.kind, candidate.body) == null) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    try {
      validateSyncReviewCandidateBody(candidate.kind, candidate.body);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    final localCandidate = await _localNaturalCandidate(
      kind: currentRow.kind,
      id: currentRow.recordId,
    );
    if (localCandidate == null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    if (currentRow.localHash == null ||
        localCandidate.wireHash != currentRow.localHash) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    final localAddress = (kind: currentRow.kind, recordId: currentRow.recordId);
    final localBody = await read(localAddress);
    final localMetadata = await _naturalRecordMetadata(
      currentRow.kind,
      currentRow.recordId,
    );
    if (localBody == null ||
        localMetadata == null ||
        localMetadata.deletedAt != null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    if (localMetadata.existenceAt.isAfter(candidate.existenceAt)) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    final queuedCandidateAddress = (
      kind: candidate.kind,
      recordId: candidate.id,
    );
    if (await repositories.syncLocal.resolveAlias(
          kind: candidate.kind,
          recordId: candidate.id,
        ) !=
        candidate.id) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    if (await read(queuedCandidateAddress) != null) {
      throw const SyncReviewException(
        SyncReviewFailureCode.candidateAlreadyPresent,
      );
    }
    final candidateKey = syncNaturalKeyForBody(candidate.kind, candidate.body)!;
    final localKey = syncNaturalKeyForBody(currentRow.kind, localBody);
    if (localKey == null || localKey != candidateKey) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }

    var candidateForApply = candidate;
    switch (action) {
      case SyncReviewAction.merge:
        final localIdentity = await _recordIdentity(
          currentRow.kind,
          currentRow.recordId,
        );
        if (localIdentity == null) {
          throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
        }
        final canonicalDifficultyId =
            currentRow.kind == SyncRecordKind.difficultyLevel
            ? _canonicalDifficultyId(
                candidateKey,
                candidateId: candidate.id,
                incumbentId: currentRow.recordId,
              )
            : null;
        // Resolved through the alias chain for the same reason inbound
        // reconciliation resolves its own: `_adoptCollision` adopts onto the
        // end of the chain, so adopting towards a retired ID here and then
        // writing the candidate under the raw one splits a single natural key
        // across two rows. A shipped difficulty ID is the reachable case —
        // `_canonicalDifficultyId` names it without consulting the aliases —
        // but `currentRow.recordId` is never checked for being chain-terminal
        // either, so the resolution is applied to whichever ID wins.
        final survivorId = await repositories.syncLocal.resolveAlias(
          kind: currentRow.kind,
          recordId:
              canonicalDifficultyId ??
              (currentRow.recordId.compareTo(candidate.id) <= 0
                  ? currentRow.recordId
                  : candidate.id),
        );
        final aliases = <SyncRecordKind, Map<String, String>>{};
        if (currentRow.recordId != survivorId) {
          await _adoptCollision(
            kind: currentRow.kind,
            losingId: currentRow.recordId,
            survivingId: survivorId,
            aliases: aliases,
            localIdentity: localIdentity,
          );
        }
        if (candidate.id != survivorId) {
          await _adoptCollision(
            kind: currentRow.kind,
            losingId: candidate.id,
            survivingId: survivorId,
            aliases: aliases,
          );
          candidateForApply = _rewriteCandidateIdentity(
            SyncMergeCandidate(blob: candidate),
            survivorId,
            aliases,
            preserveUpdatedAt: true,
          ).blob;
        }
        break;
      case SyncReviewAction.keepBoth:
        var renamedKey = _validatedReviewName(
          newNaturalKey,
          currentKey: localKey,
        );
        if (currentRow.kind == SyncRecordKind.customFieldDef) {
          renamedKey = renamedKey.trim();
          if (!isValidCustomFieldKey(renamedKey)) {
            throw const SyncReviewException(
              SyncReviewFailureCode.invalidCustomFieldKey,
            );
          }
        }
        final occupied = await _naturalKeyRow(
          currentRow.kind,
          normalizeShareableText(renamedKey).toLowerCase(),
        );
        if (occupied != null) {
          throw const SyncReviewException(
            SyncReviewFailureCode.nameNotDistinct,
          );
        }
        await _renameLocalNaturalKey(
          currentRow.kind,
          currentRow.recordId,
          renamedKey,
        );
    }

    final candidateAddress = (
      kind: candidateForApply.kind,
      recordId: candidateForApply.id,
    );
    final currentCandidateBody = Map<String, Object?>.from(
      await read(candidateAddress) ?? const {},
    );
    final report = await writeWithReport(
      SyncApplyRecord(
        address: candidateAddress,
        body: _overlay(currentCandidateBody, candidateForApply.body),
        updatedAt: candidateForApply.updatedAt,
        deletedAt: candidateForApply.deletedAt,
        existenceAt: candidateForApply.existenceAt,
        sourceBlob: candidateForApply,
      ),
    );
    if (report != null) {
      throw StateError(report.message);
    }
    await rebuildDerivedIndexes();
    await repositories.syncLocal.deleteReview(
      kind: currentRow.kind,
      recordId: currentRow.recordId,
      counterpartId: currentRow.counterpartId,
    );
  });

  /// Resolves a sync-spec §6.6 **step-1** rename collision: a record whose
  /// UUID this device already knows arrived carrying a natural key that
  /// another local row holds.
  ///
  /// The identity layout is the mirror of every other queued reason, and that
  /// is the whole reason this is a separate method rather than another branch
  /// of [resolveReviewQueue]'s tombstone path. Here `record_id` is the local
  /// row the candidate updates — and the candidate's own id — while
  /// `counterpart_id` is the *other* local row, the one holding the colliding
  /// name. The tombstone path assumes the opposite on both counts.
  ///
  /// Both sides being pre-existing local rows is also what forbids the silent
  /// merge (§6.6, ADR-004: "they may be two different people"), and what makes
  /// the merge action below pass a non-null `localIdentity` for the losing
  /// side. [resolveReviewQueue]'s own merge passes `null` for its candidate,
  /// correctly, because there the candidate is not a local row; copying that
  /// here would leave `_rewriteLocalReferences` repointing join rows at an id
  /// whose row is still standing under its own identity.
  Future<void> _resolveNaturalKeyRenameCollision({
    required ReviewQueueRow currentRow,
    required SyncReviewAction action,
    required String? newNaturalKey,
  }) async {
    final kind = currentRow.kind;
    final SyncRecordBlob candidate;
    try {
      candidate = decodeSyncRecordBlob(currentRow.candidateBlob);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    if (candidate.kind != kind ||
        candidate.id != currentRow.recordId ||
        candidate.body['id'] != candidate.id ||
        candidate.deletedAt != null ||
        currentRow.recordId == currentRow.counterpartId ||
        currentRow.candidateHash !=
            sha256Hex(encodeSyncRecordBlobUtf8(candidate)) ||
        !syncNaturalKeyKinds.contains(kind) ||
        syncNaturalKeyForBody(kind, candidate.body) == null ||
        (currentRow.reason == syncShippedDifficultyRenameCollisionReason &&
            kind != SyncRecordKind.difficultyLevel)) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    try {
      validateSyncReviewCandidateBody(kind, candidate.body);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    final candidateKey = syncNaturalKeyForBody(kind, candidate.body)!;

    // §6.6's local-version check. The hash was captured at enqueue against
    // this same row — the one the pass deliberately did not write — so a user
    // edit since then invalidates the decision. A NULL legacy value fails the
    // same way a mismatch does, rather than being treated as "no opinion".
    final localTarget = await _localNaturalCandidate(
      kind: kind,
      id: currentRow.recordId,
    );
    final targetMetadata = await _naturalRecordMetadata(
      kind,
      currentRow.recordId,
    );
    if (localTarget == null ||
        targetMetadata == null ||
        targetMetadata.deletedAt != null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    if (currentRow.localHash == null ||
        localTarget.wireHash != currentRow.localHash) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }

    final holder = await _localNaturalCandidate(
      kind: kind,
      id: currentRow.counterpartId,
    );
    final holderMetadata = await _naturalRecordMetadata(
      kind,
      currentRow.counterpartId,
    );
    if (holder == null || holderMetadata == null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    // A **tombstoned** holder is not a missing one, and rejecting it as such
    // reproduced this issue's own disease inside its fix: the row stayed
    // queued and neither action could clear it.
    //
    // None of the four natural-key indexes is filtered on `deleted_at`
    // (§4.1), so a tombstone keeps occupying its name — which is how this
    // collision arises at all — and `_loadNaturalKeyIndex` selects every row,
    // preferring a live one only when there is a live one to prefer. A peer
    // renaming a known UUID onto a name that only a deleted row holds
    // therefore reaches the step-1 guard with a deleted incumbent, and that
    // guard does not filter on it either.
    final holderDeleted = holderMetadata.deletedAt != null;
    // The collision must still exist. Renaming one side by hand was the only
    // workaround available before this action shipped, so it is a reachable
    // state rather than a theoretical one, and applying the candidate then
    // would be answering a question nobody is asking any more.
    if (syncNaturalKeyForBody(kind, holder.blob.body) != candidateKey) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    for (final id in [currentRow.recordId, currentRow.counterpartId]) {
      if (await repositories.syncLocal.resolveAlias(kind: kind, recordId: id) !=
          id) {
        throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
      }
    }

    var candidateForApply = candidate;
    switch (action) {
      case SyncReviewAction.merge:
        if (holderDeleted) {
          // Collapsing a live record and a tombstone into one row is an
          // **existence** decision, which §6.4 and §6.6 step 2 settle by
          // comparing `existenceAt`. Step 1 runs none of that machinery on
          // purpose: it does not reconcile bodies at all, because the two rows
          // may be different entities.
          //
          // So there is no sound thing to do here. Adopting the tombstone onto
          // a live survivor resurrects a deletion the user made — its id would
          // resolve through the alias to a live row — while letting the
          // tombstone survive deletes the live row instead. Either way an
          // existence question gets answered by a tie-break that was never
          // meant to answer one. Keep both frees the name without deciding it,
          // and stays available.
          throw const SyncReviewException(
            SyncReviewFailureCode.counterpartDeleted,
          );
        }
        // A shipped difficulty ID outranks the lexicographic rule: it is part
        // of the persisted relationship contract (§6.6), which is exactly what
        // the shipped-difficulty variant of this reason exists to hold open.
        final canonicalDifficultyId = kind == SyncRecordKind.difficultyLevel
            ? _canonicalDifficultyId(
                candidateKey,
                candidateId: currentRow.recordId,
                incumbentId: currentRow.counterpartId,
              )
            : null;
        final survivorId = await repositories.syncLocal.resolveAlias(
          kind: kind,
          recordId:
              canonicalDifficultyId ??
              (currentRow.recordId.compareTo(currentRow.counterpartId) <= 0
                  ? currentRow.recordId
                  : currentRow.counterpartId),
        );
        final aliases = <SyncRecordKind, Map<String, String>>{};
        for (final losingId in [
          currentRow.recordId,
          currentRow.counterpartId,
        ]) {
          if (losingId == survivorId) continue;
          // §6.6: "Step 1 involves two pre-existing local rows and MUST NOT
          // coalesce." `_adoptCollision` obliges on its own — with the
          // survivor's row already standing it takes `_deleteIdentityRow`,
          // which does not carry the loser's `deviceLocal` contact fields
          // across. The identity is re-read per iteration because the previous
          // iteration may have moved it.
          await _adoptCollision(
            kind: kind,
            losingId: losingId,
            survivingId: survivorId,
            aliases: aliases,
            localIdentity: await _recordIdentity(kind, losingId),
          );
        }
        if (candidate.id != survivorId) {
          candidateForApply = _rewriteCandidateIdentity(
            SyncMergeCandidate(blob: candidate),
            survivorId,
            aliases,
            preserveUpdatedAt: true,
          ).blob;
        }
      case SyncReviewAction.keepBoth:
        var renamedKey = _validatedReviewName(
          newNaturalKey,
          currentKey: candidateKey,
        );
        if (kind == SyncRecordKind.customFieldDef) {
          renamedKey = renamedKey.trim();
          if (!isValidCustomFieldKey(renamedKey)) {
            throw const SyncReviewException(
              SyncReviewFailureCode.invalidCustomFieldKey,
            );
          }
        }
        // Occupancy is tested against every row, not just the two in this
        // decision: the natural-key indexes are not filtered on `deleted_at`,
        // so a tombstoned row still holds its name and the rename would fail
        // at the database rather than as a diagnosable review outcome.
        final occupied = await _naturalKeyRow(
          kind,
          normalizeShareableText(renamedKey).toLowerCase(),
        );
        if (occupied != null) {
          throw const SyncReviewException(
            SyncReviewFailureCode.nameNotDistinct,
          );
        }
        // The row being renamed is the *counterpart* — the one holding the
        // name — so the candidate can then be applied to `record_id` unchanged.
        //
        // This works on a tombstoned holder too, and is the only action that
        // does: freeing the name asks no question about which record exists,
        // so nothing has to be decided that step 1 cannot decide. The rename
        // does restamp the tombstone and republish it, which is the honest
        // consequence of the user renaming a record — deleted or not.
        await _renameLocalNaturalKey(
          kind,
          currentRow.counterpartId,
          renamedKey,
        );
    }

    final candidateAddress = (
      kind: candidateForApply.kind,
      recordId: candidateForApply.id,
    );
    final currentCandidateBody = Map<String, Object?>.from(
      await read(candidateAddress) ?? const {},
    );
    final report = await writeWithReport(
      SyncApplyRecord(
        address: candidateAddress,
        body: _overlay(currentCandidateBody, candidateForApply.body),
        updatedAt: candidateForApply.updatedAt,
        deletedAt: candidateForApply.deletedAt,
        existenceAt: candidateForApply.existenceAt,
        sourceBlob: candidateForApply,
      ),
    );
    if (report != null) {
      throw StateError(report.message);
    }
    await rebuildDerivedIndexes();
    await repositories.syncLocal.deleteReview(
      kind: currentRow.kind,
      recordId: currentRow.recordId,
      counterpartId: currentRow.counterpartId,
    );
  }

  Future<void> _resolveDanceAmbiguity({
    required ReviewQueueRow currentRow,
    required SyncReviewAction action,
    required String? newNaturalKey,
  }) async {
    final SyncRecordBlob queuedCandidate;
    try {
      queuedCandidate = decodeSyncRecordBlob(currentRow.candidateBlob);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    if (currentRow.kind != SyncRecordKind.dance ||
        queuedCandidate.kind != SyncRecordKind.dance ||
        queuedCandidate.id != currentRow.counterpartId ||
        queuedCandidate.body['id'] != queuedCandidate.id ||
        queuedCandidate.deletedAt != null ||
        currentRow.recordId == queuedCandidate.id ||
        currentRow.candidateHash !=
            sha256Hex(encodeSyncRecordBlobUtf8(queuedCandidate))) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    try {
      validateSyncReviewCandidateBody(
        SyncRecordKind.dance,
        queuedCandidate.body,
      );
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }

    final local = await _danceCandidate(currentRow.recordId);
    final currentCandidate = await _danceCandidate(queuedCandidate.id);
    if (local == null ||
        local.blob.deletedAt != null ||
        currentCandidate == null ||
        currentCandidate.blob.deletedAt != null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    if (currentCandidate.wireHash != currentRow.candidateHash ||
        currentRow.localHash == null ||
        local.wireHash != currentRow.localHash ||
        await repositories.syncLocal.resolveAlias(
              kind: SyncRecordKind.dance,
              recordId: local.blob.id,
            ) !=
            local.blob.id ||
        await repositories.syncLocal.resolveAlias(
              kind: SyncRecordKind.dance,
              recordId: currentCandidate.blob.id,
            ) !=
            currentCandidate.blob.id) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }

    final localTitle = local.blob.body['title'];
    final candidateTitle = currentCandidate.blob.body['title'];
    if (localTitle is! String ||
        candidateTitle is! String ||
        normalizeTitle(localTitle) != normalizeTitle(candidateTitle)) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }

    switch (action) {
      case SyncReviewAction.merge:
        final merge = mergeDanceCandidates([local, currentCandidate]);
        final aliases = <String, String>{
          for (final losingId in merge.losingIds)
            losingId: merge.winner.blob.id,
        };
        await _applyDanceDedupeMerge(merge, aliases);
      case SyncReviewAction.keepBoth:
        final renamedTitle = _validatedDanceTitle(
          newNaturalKey,
          currentKey: normalizeTitle(candidateTitle),
        );
        if (await _danceTitleOccupied(
          normalizeTitle(renamedTitle),
          excludingId: local.blob.id,
        )) {
          throw const SyncReviewException(
            SyncReviewFailureCode.nameNotDistinct,
          );
        }
        await _renameLocalDanceTitle(local.blob.id, renamedTitle);
        await _reconcileDanceReviewQueue(
          survivorId: local.blob.id,
          losingIds: const {},
        );
    }
    await rebuildDerivedIndexes();
    await repositories.syncLocal.deleteReview(
      kind: currentRow.kind,
      recordId: currentRow.recordId,
      counterpartId: currentRow.counterpartId,
    );
  }

  /// [withheld], when given, collects a report for a dance refused here
  /// because its stored content cannot be decoded (#1347).
  ///
  /// It is optional because two of this method's three callers must not raise
  /// one. `_reconcileDanceReviewQueue` runs after a merge inside
  /// [deduplicateFreshAttach], which has already reported the same record from
  /// its dedupe plan — a second report would carry an identical
  /// [SyncReport.coalescingKey] and be dropped anyway, so passing a sink there
  /// would add a path without adding a notice. `resolveDanceReview` is a user
  /// gesture rather than a pass: it raises
  /// `SyncReviewException(targetMissing)` and has no report sink to fill.
  Future<SyncMergeCandidate?> _danceCandidate(
    String id, {
    List<SyncReport>? withheld,
  }) async {
    final dance = await repositories.dances.getById(id, includeDeleted: true);
    if (dance == null) return null;
    // Withheld for the same reason [_readDanceBody] withholds: this device
    // cannot read the row it would be speaking for, and the body it would build
    // carries the transcription as an empty array beside a `figuresRaw` sibling.
    // A peer that does not understand `figuresRaw` applies the empty array over
    // its own readable copy (#1347).
    //
    // These two paths do not go through [_readDanceBody], so they are not
    // covered by its guard, and they became reachable only because this change
    // made `listAll`/`getById` return such a dance instead of raising.
    //
    // Consequence, stated rather than implied: an undecodable dance is not
    // offered as a merge candidate. Conservative in the same direction as the
    // withhold — the record is simply not spoken for, and [withheld] is how it
    // stops being spoken for *silently* (#1347).
    if (dance.figuresSource is UnreadableFigures ||
        dance.tunesSource is UnreadableTunes) {
      withheld?.add(_withheldUnreadableDanceReport(id));
      return null;
    }
    final row = await (_db.select(
      _db.dances,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final customFields = await repositories.customFieldDefs
        .listAllWithDeleted();
    final allowedCustomFieldIds = {
      for (final entry in customFields)
        if (entry.field.shareable && !entry.deleted) entry.field.id,
    };
    final blob = syncRecordBlobForEntity(
      SyncRecordKind.dance,
      dance,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      existenceAt: row.existenceAt ?? row.updatedAt,
      allowedCustomFieldIds: allowedCustomFieldIds,
    );
    return blob == null ? null : SyncMergeCandidate(blob: blob);
  }

  String _validatedDanceTitle(String? raw, {required String currentKey}) {
    if (raw == null) {
      throw const SyncReviewException(SyncReviewFailureCode.nameRequired);
    }
    final normalized = normalizeShareableText(raw).trim();
    if (normalized.isEmpty) {
      throw const SyncReviewException(SyncReviewFailureCode.nameRequired);
    }
    if (normalizeTitle(normalized) == currentKey) {
      throw const SyncReviewException(SyncReviewFailureCode.nameNotDistinct);
    }
    return normalized;
  }

  Future<bool> _danceTitleOccupied(
    String normalizedTitle, {
    required String excludingId,
  }) async {
    final rows = await _db.select(_db.dances).get();
    return rows.any(
      (row) =>
          row.id != excludingId &&
          row.deletedAt == null &&
          normalizeTitle(row.title) == normalizedTitle,
    );
  }

  Future<void> _renameLocalDanceTitle(String id, String title) async {
    final row = await (_db.select(
      _db.dances,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    await (_db.update(_db.dances)..where((table) => table.id.equals(id))).write(
      DancesCompanion(
        title: Value(normalizeShareableText(title)),
        updatedAt: Value(
          nextExistenceStamp(
            now: DateTime.now().toUtc(),
            current: row.updatedAt,
          ),
        ),
      ),
    );
  }

  bool _sameReviewQueueRow(ReviewQueueRow left, ReviewQueueRow right) =>
      left.kind == right.kind &&
      left.recordId == right.recordId &&
      left.counterpartId == right.counterpartId &&
      left.reason == right.reason &&
      left.candidateBlob == right.candidateBlob &&
      left.candidateHash == right.candidateHash &&
      left.localHash == right.localHash &&
      left.queuedAt == right.queuedAt;

  String _validatedReviewName(String? raw, {required String currentKey}) {
    if (raw == null) {
      throw const SyncReviewException(SyncReviewFailureCode.nameRequired);
    }
    final normalized = normalizeShareableText(raw).trim();
    if (normalized.isEmpty) {
      throw const SyncReviewException(SyncReviewFailureCode.nameRequired);
    }
    if (normalizeShareableText(normalized).toLowerCase() == currentKey) {
      throw const SyncReviewException(SyncReviewFailureCode.nameNotDistinct);
    }
    return normalized;
  }

  Future<void> _renameLocalNaturalKey(
    SyncRecordKind kind,
    String id,
    String value,
  ) async {
    final normalized = normalizeShareableText(value);
    final stamp = nextExistenceStamp(
      now: DateTime.now().toUtc(),
      current: (await _naturalRecordMetadata(kind, id))?.updatedAt,
    );
    switch (kind) {
      case SyncRecordKind.choreographer:
        await (_db.update(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).write(
          ChoreographersCompanion(
            name: Value(normalized),
            updatedAt: Value(stamp),
          ),
        );
      case SyncRecordKind.tag:
        await (_db.update(_db.tags)..where((row) => row.id.equals(id))).write(
          TagsCompanion(name: Value(normalized), updatedAt: Value(stamp)),
        );
      case SyncRecordKind.customFieldDef:
        await (_db.update(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).write(
          CustomFieldDefsCompanion(
            key: Value(normalized),
            updatedAt: Value(stamp),
          ),
        );
      case SyncRecordKind.difficultyLevel:
        await (_db.update(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).write(
          DifficultyLevelsCompanion(
            label: Value(normalized),
            updatedAt: Value(stamp),
          ),
        );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        throw const SyncReviewException(
          SyncReviewFailureCode.unsupportedReason,
        );
    }
    if (_naturalKeyIndex != null) {
      final identity = await _recordIdentity(kind, id);
      if (identity != null) {
        _naturalKeyIndex!.replace(
          kind: kind,
          id: id,
          key: normalized.toLowerCase(),
          type: identity.type,
          deleted: identity.deleted,
          shareable: identity.shareable,
        );
      }
    }
  }

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) async {
    if (address.kind == SyncRecordKind.setting) {
      final row =
          await (_db.select(_db.settings)
                ..where((table) => table.key.equals(address.recordId)))
              .getSingleOrNull();
      return row == null ? null : {'value': jsonDecode(row.valueJson)};
    }

    final body = switch (address.kind) {
      SyncRecordKind.dance => await _readDanceBody(address.recordId),
      SyncRecordKind.program => await _readProgramBody(address.recordId),
      SyncRecordKind.choreographer => await _readChoreographerBody(
        address.recordId,
      ),
      SyncRecordKind.tag => await _readTagBody(address.recordId),
      SyncRecordKind.publishedSource => await _readPublishedSourceBody(
        address.recordId,
      ),
      SyncRecordKind.customFieldDef => await _readCustomFieldBody(
        address.recordId,
      ),
      SyncRecordKind.difficultyLevel => await _readDifficultyBody(
        address.recordId,
      ),
      SyncRecordKind.venue => await _readVenueBody(address.recordId),
      SyncRecordKind.setting => throw StateError('handled above'),
    };
    return body;
  }

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>>
  snapshotCandidates() async {
    // The concurrency guard compares this against the coordinator's
    // `expectedWireHashes`, which is built from the local candidates *and* the
    // pending-live ones. Returning only `local` — which `snapshot()`
    // deliberately strips every pending-deletion address out of — made the
    // guard read `null` for exactly those addresses while the coordinator had
    // supplied a real hash, so every inbound update to a record held live by
    // the §6.8 referential guard was refused as a concurrent local change on
    // every pass, over a record the user had not touched. Nothing changes
    // between the two reads; the mismatch was structural.
    final current = await snapshot();
    return {...current.local, ...current.pendingLive};
  }

  Future<_NaturalKeyIndex> _loadNaturalKeyIndex() async {
    final index = _NaturalKeyIndex({});
    final choreographers = await _db.select(_db.choreographers).get();
    for (final row in choreographers) {
      index.add(
        kind: SyncRecordKind.choreographer,
        key: normalizeShareableText(row.name).toLowerCase(),
        value: (
          id: row.id,
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        ),
      );
    }
    final tags = await _db.select(_db.tags).get();
    for (final row in tags) {
      index.add(
        kind: SyncRecordKind.tag,
        key: normalizeShareableText(row.name).toLowerCase(),
        value: (
          id: row.id,
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        ),
      );
    }
    final customFields = await _db.select(_db.customFieldDefs).get();
    for (final row in customFields) {
      index.add(
        kind: SyncRecordKind.customFieldDef,
        key: normalizeShareableText(row.key).toLowerCase(),
        value: (
          id: row.id,
          type: row.type.name,
          deleted: row.deletedAt != null,
          shareable: row.shareable,
        ),
      );
    }
    final difficultyLevels = await _db.select(_db.difficultyLevels).get();
    for (final row in difficultyLevels) {
      index.add(
        kind: SyncRecordKind.difficultyLevel,
        key: normalizeShareableText(row.label).toLowerCase(),
        value: (
          id: row.id,
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        ),
      );
    }
    return index;
  }

  @override
  Future<SyncApplyPreparation> reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) async {
    final previousNaturalKeyIndex = _naturalKeyIndex;
    _naturalKeyIndex = await _loadNaturalKeyIndex();
    _inboundTombstonedAddresses = {};
    try {
      return await _reconcileInbound(
        candidates,
        expectedWireHashes: expectedWireHashes,
      );
    } finally {
      _naturalKeyIndex = previousNaturalKeyIndex;
    }
  }

  Future<SyncApplyPreparation> _reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) async {
    final aliases = await _aliasMap();
    final baseline = await repositories.syncLocal.snapshotBaseline();
    final prepared = <SyncMergeCandidate>[];
    final reports = <SyncReport>[];
    final preparedNatural = <({SyncRecordKind kind, String key}), int>{};
    for (var candidate in candidates) {
      final preflight = _preflightInboundCandidate(candidate);
      final preflightReport = preflight.report;
      if (preflightReport != null) {
        if (candidate.blob.kind == SyncRecordKind.customFieldDef &&
            candidate.blob.body['shareable'] == false &&
            preflightReport.code == SyncReportCode.invalidClassification) {
          // Keep the rejected definition in the validation context so
          // dependent inbound dances receive the same classification report.
          // It must not enter natural-key reconciliation, which can migrate
          // local identities before the final semantic validation.
          prepared.add(candidate);
        } else {
          reports.add(preflightReport);
        }
        continue;
      }
      candidate = preflight.candidate!;
      final kind = candidate.blob.kind;
      if (syncNaturalKeyKinds.contains(kind)) {
        final originalAddress = candidate.address;
        candidate = _rewriteCandidate(candidate, aliases);
        if (candidate.address != originalAddress &&
            !await _guardReconciliationTarget(
              kind: candidate.blob.kind,
              recordId: candidate.blob.id,
              expectedWireHashes: expectedWireHashes,
              reports: reports,
            )) {
          continue;
        }
        final inboundCandidateId = candidate.blob.id;
        final naturalKey = syncNaturalKeyForBody(kind, candidate.blob.body);
        if (naturalKey != null) {
          final byId = await _recordIdentity(kind, candidate.blob.id);
          final incumbent = await _naturalKeyRow(kind, naturalKey);

          if (kind == SyncRecordKind.difficultyLevel &&
              incumbent != null &&
              candidate.blob.id != incumbent.id &&
              DifficultyLevel.shippedIds.contains(candidate.blob.id) &&
              DifficultyLevel.shippedIds.contains(incumbent.id)) {
            await _enqueueCollisionReview(
              candidate,
              incumbent.id,
              reason: 'two distinct shipped difficulty IDs share a natural key',
            );
            continue;
          }

          // Shipped difficulty IDs are part of the persisted relationship
          // contract and outrank a same-label custom ID.
          //
          // The result is resolved through the alias chain: a shipped ID an
          // earlier collision already retired is not a usable survivor, and
          // `_adoptCollision` resolves its own target, so leaving this one raw
          // would migrate the local row to the end of the chain while the
          // inbound record adopted the retired ID — two rows, one natural key.
          final rawCanonicalDifficultyId =
              kind == SyncRecordKind.difficultyLevel
              ? _canonicalDifficultyId(
                  naturalKey,
                  candidateId: candidate.blob.id,
                  incumbentId: incumbent?.id,
                )
              : null;
          final canonicalDifficultyId = rawCanonicalDifficultyId == null
              ? null
              : _resolveInMap(rawCanonicalDifficultyId, aliases[kind]);
          if (canonicalDifficultyId != null) {
            if (byId != null && incumbent != null && byId.id != incumbent.id) {
              await _enqueueCollisionReview(
                candidate,
                incumbent.id,
                reason: syncShippedDifficultyRenameCollisionReason,
              );
              continue;
            }
            if (incumbent != null) {
              if (candidate.blob.deletedAt != null &&
                  !incumbent.deleted &&
                  !baseline.containsKey((kind: kind, recordId: incumbent.id)) &&
                  await _tombstoneOutranksLocalCreation(
                    kind,
                    incumbent.id,
                    candidate.blob,
                  )) {
                await _enqueueCollisionReview(
                  candidate,
                  candidate.blob.id,
                  recordId: incumbent.id,
                  reason: syncBaselineAbsenceTombstoneReason,
                );
                continue;
              }
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: incumbent.id,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              final localCandidate = await _localNaturalCandidate(
                kind: kind,
                id: incumbent.id,
              );
              if (localCandidate == null) continue;
              final reconciled = await _reconcileNaturalKeyCollision(
                candidate: candidate,
                local: localCandidate,
                survivorId: canonicalDifficultyId,
              );
              if (reconciled == null) continue;
              candidate = reconciled;
            }
            if (incumbent != null && incumbent.id != canonicalDifficultyId) {
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: canonicalDifficultyId,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              await _adoptCollision(
                kind: kind,
                losingId: incumbent.id,
                survivingId: canonicalDifficultyId,
                aliases: aliases,
                localIdentity: incumbent,
              );
            }
            if (inboundCandidateId != canonicalDifficultyId &&
                inboundCandidateId != incumbent?.id) {
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: inboundCandidateId,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              await _adoptCollision(
                kind: kind,
                losingId: inboundCandidateId,
                survivingId: canonicalDifficultyId,
                aliases: aliases,
                localIdentity: byId,
              );
            }
            candidate = _rewriteCandidateIdentity(
              candidate,
              canonicalDifficultyId,
              aliases,
            );
          } else if (byId != null &&
              incumbent != null &&
              incumbent.id != candidate.blob.id) {
            await _enqueueCollisionReview(
              candidate,
              incumbent.id,
              reason: syncNaturalKeyRenameCollisionReason,
            );
            continue;
          } else if (incumbent != null &&
              kind == SyncRecordKind.customFieldDef &&
              incumbent.shareable == false &&
              candidate.blob.body['shareable'] == true) {
            if (incumbent.id == candidate.blob.id) {
              await _enqueueCollisionReview(
                candidate,
                incumbent.id,
                reason:
                    'a shareable inbound definition cannot replace a '
                    'private local definition',
              );
              continue;
            }
            // The *private local* definition is the one that yields its key.
            //
            // Renaming the inbound definition instead — which is what this did
            // until #1355 — decides "which record survives" on local versus
            // incoming, which ADR-004 and §6.6 forbid because it does not
            // converge. It also stamped the renamed copy with this device's
            // clock, so ordinary last-writer-wins republished it and every
            // peer had its shared field renamed on account of a private row
            // only this device holds.
            //
            // Renaming the private row is symmetric in effect rather than in
            // form: a private definition never reaches the wire
            // (`projectShareableRecordBody` returns an empty body for it), so
            // no peer can observe the collision at all and every device agrees
            // on the shared definition's bare key. The suffix therefore
            // derives from the private definition's own UUID.
            final renamed = await _renameLocalPrivateCustomField(
              candidate,
              incumbent,
            );
            if (!renamed) continue;
          } else if (incumbent != null && incumbent.id != candidate.blob.id) {
            if (candidate.blob.deletedAt != null &&
                !incumbent.deleted &&
                !baseline.containsKey((kind: kind, recordId: incumbent.id)) &&
                await _tombstoneOutranksLocalCreation(
                  kind,
                  incumbent.id,
                  candidate.blob,
                )) {
              await _enqueueCollisionReview(
                candidate,
                candidate.blob.id,
                recordId: incumbent.id,
                reason: syncBaselineAbsenceTombstoneReason,
              );
              continue;
            }
            if (!await _guardReconciliationTarget(
              kind: kind,
              recordId: incumbent.id,
              expectedWireHashes: expectedWireHashes,
              reports: reports,
            )) {
              continue;
            }

            if (kind == SyncRecordKind.customFieldDef &&
                incumbent.type != _customFieldType(candidate.blob.body)) {
              final reconciled = await _reconcileCustomFieldTypeMismatch(
                candidate,
                incumbent,
              );
              if (reconciled == null) continue;
              candidate = reconciled;
            } else {
              final localCandidate = await _localNaturalCandidate(
                kind: kind,
                id: incumbent.id,
              );
              if (localCandidate == null) {
                continue;
              }
              final survivingId = candidate.blob.id.compareTo(incumbent.id) < 0
                  ? candidate.blob.id
                  : incumbent.id;
              final reconciled = await _reconcileNaturalKeyCollision(
                candidate: candidate,
                local: localCandidate,
                survivorId: survivingId,
              );
              if (reconciled == null) continue;
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: survivingId,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              await _adoptCollision(
                kind: kind,
                losingId: survivingId == candidate.blob.id
                    ? incumbent.id
                    : candidate.blob.id,
                survivingId: survivingId,
                aliases: aliases,
                localIdentity: survivingId == incumbent.id ? null : incumbent,
              );
              candidate = reconciled;
            }
          }
        }
      } else {
        candidate = _rewriteCandidate(candidate, aliases);
      }
      final naturalKey = syncNaturalKeyKinds.contains(kind)
          ? syncNaturalKeyForBody(kind, candidate.blob.body)
          : null;
      if (naturalKey != null) {
        final naturalAddress = (kind: kind, key: naturalKey);
        final previousIndex = preparedNatural[naturalAddress];
        if (previousIndex != null) {
          final previous = prepared[previousIndex];
          if (kind == SyncRecordKind.customFieldDef &&
              _customFieldType(previous.blob.body) !=
                  _customFieldType(candidate.blob.body)) {
            final incomingWins =
                candidate.blob.id.compareTo(previous.blob.id) < 0;
            final losing = incomingWins ? previous : candidate;
            final losingKey = losing.blob.body['key'];
            if (losingKey is! String) continue;
            final shortKey = syncCustomFieldSuffix(
              losingKey,
              losing.blob.id,
              full: false,
            );
            final fullKey = syncCustomFieldSuffix(
              losingKey,
              losing.blob.id,
              full: true,
            );
            Future<bool> isOccupied(String key) async {
              final address = (
                kind: SyncRecordKind.customFieldDef,
                key: key.toLowerCase(),
              );
              if (preparedNatural.containsKey(address) &&
                  preparedNatural[address] != previousIndex) {
                return true;
              }
              return await _naturalKeyRow(
                    SyncRecordKind.customFieldDef,
                    key.toLowerCase(),
                  ) !=
                  null;
            }

            final suffix = !await isOccupied(shortKey)
                ? shortKey
                : !await isOccupied(fullKey)
                ? fullKey
                : null;
            if (suffix == null) {
              await _enqueueCollisionReview(
                candidate,
                previous.blob.id,
                reason:
                    'custom-field type mismatch has no deterministic free key',
              );
              continue;
            }
            final losingBody = Map<String, Object?>.from(losing.blob.body)
              ..['key'] = suffix;
            final renamed = _candidateWithBody(
              losing,
              losing.blob.id,
              losingBody,
              updatedAt: nextExistenceStamp(
                now: DateTime.now().toUtc(),
                current: losing.blob.updatedAt,
              ),
            );
            if (incomingWins) {
              prepared[previousIndex] = renamed;
              preparedNatural.remove(naturalAddress);
              preparedNatural[(
                    kind: SyncRecordKind.customFieldDef,
                    key: suffix.toLowerCase(),
                  )] =
                  previousIndex;
              preparedNatural[naturalAddress] = prepared.length;
            } else {
              candidate = renamed;
              preparedNatural[(
                    kind: SyncRecordKind.customFieldDef,
                    key: suffix.toLowerCase(),
                  )] =
                  prepared.length;
            }
          } else {
            // §6.6 step 1 applies in-batch, not only against stored rows.
            // The step-1 guard above consults `_naturalKeyRow`, which is
            // served from an index built from stored rows alone
            // (`_loadNaturalKeyIndex`), and a candidate that is merely
            // *prepared* never enters it. So two locally-known rows renamed
            // onto one previously-unused name by two peers both miss that
            // guard and arrive here, where the merge below would pick the
            // lexicographically smaller UUID and `_adoptCollision` would
            // reach `_deleteIdentityRow` — the branch that does not copy
            // `deviceLocal` fields. The loser's email, location and deceased
            // flag are held nowhere else (they are stripped from every
            // shareable body), so the silent merge destroyed them and joined
            // two possibly different people into one record.
            //
            // Both sides being pre-existing local rows is exactly what §6.6
            // step 1 and ADR-004 forbid coalescing, so route the later
            // candidate to the review queue instead, with the same reason the
            // stored-row guard uses. The earlier candidate stays prepared,
            // which reproduces the end state the stored-row path already
            // produces when the two renames arrive in separate passes.
            //
            // The identity test is on distinct ids on purpose. Difficulty
            // canonicalization rewrites a candidate onto a shipped ID, so two
            // peers' same-label custom rows can both arrive here already
            // carrying that one ID. Both then resolve to the same local row,
            // and a guard that only asked "are both known?" would queue a
            // review for a pair that collapses harmlessly — `_adoptCollision`
            // returns immediately when the losing and surviving ids are equal.
            if (previous.blob.id != candidate.blob.id &&
                await _recordIdentity(kind, previous.blob.id) != null &&
                await _recordIdentity(kind, candidate.blob.id) != null) {
              await _enqueueCollisionReview(
                candidate,
                previous.blob.id,
                reason: syncNaturalKeyRenameCollisionReason,
              );
              continue;
            }
            final survivingId =
                candidate.blob.id.compareTo(previous.blob.id) < 0
                ? candidate.blob.id
                : previous.blob.id;
            final reconciled = await _reconcileNaturalKeyCollision(
              candidate: candidate,
              local: previous,
              survivorId: survivingId,
            );
            if (reconciled == null) continue;
            final losingId = survivingId == candidate.blob.id
                ? previous.blob.id
                : candidate.blob.id;
            // The losing id can itself be a known local row — the ordinary
            // "a peer renamed it" case, where only one side is a pre-existing
            // local row (the both-known case returned above). Passing null
            // here skipped `_migrateLocalIdentity`/`_deleteIdentityRow`, so
            // `_rewriteLocalReferences` repointed join rows at an id that has
            // no row yet (reconciliation runs before any record is written),
            // which fails the foreign key and rolls the batch back — or, with
            // foreign keys off, leaves the local row as a ghost under the
            // losing id with its references rewritten away and the peer's
            // rename lost. `_adoptCollision`'s own comment names this hazard.
            await _adoptCollision(
              kind: kind,
              losingId: losingId,
              survivingId: survivingId,
              aliases: aliases,
              localIdentity: await _recordIdentity(kind, losingId),
            );
            prepared[previousIndex] = reconciled;
            continue;
          }
        } else {
          preparedNatural[naturalAddress] = prepared.length;
        }
      }
      prepared.add(candidate);
    }
    return SyncApplyPreparation(candidates: prepared, reports: reports);
  }

  @override
  Future<void> setInboundTombstoneContext(
    Set<SyncRecordAddress> tombstonedAddresses,
  ) async {
    _inboundTombstonedAddresses = Set<SyncRecordAddress>.of(
      tombstonedAddresses,
    );
  }

  @override
  Future<void> clearReconciliationContext() async {
    _inboundTombstonedAddresses = {};
    _remappedPendingDeletions.clear();
    _naturalKeyIndex = null;
  }

  SyncInboundCandidateAdmission _preflightInboundCandidate(
    SyncMergeCandidate candidate,
  ) {
    final admission = admitSyncInboundCandidate(candidate);
    final admissionReport = admission.report;
    if (admissionReport != null) return admission;
    final admitted = admission.candidate!;
    if (candidate.blob.kind == SyncRecordKind.customFieldDef &&
        candidate.blob.body['shareable'] == false) {
      return SyncInboundCandidateAdmission.rejected(
        SyncReport(
          code: SyncReportCode.invalidClassification,
          kind: candidate.blob.kind,
          recordId: candidate.blob.id,
          peerId: candidate.peerId,
          message:
              'Inbound custom-field definition '
              '"${candidate.blob.id}" is not shareable.',
        ),
      );
    }
    if (candidate.blob.kind == SyncRecordKind.setting) return admission;

    try {
      _decodeEntity(candidate.blob.kind, admitted.blob.body);
    } on Object catch (error) {
      return SyncInboundCandidateAdmission.rejected(
        SyncReport(
          code: SyncReportCode.malformedRecord,
          kind: candidate.blob.kind,
          recordId: candidate.blob.id,
          peerId: candidate.peerId,
          message: 'Inbound record could not be decoded: $error.',
        ),
      );
    }
    return admission;
  }

  Future<Map<SyncRecordKind, Map<String, String>>> _aliasMap() async {
    final result = <SyncRecordKind, Map<String, String>>{};
    for (final row in await repositories.syncLocal.listAliases()) {
      result.putIfAbsent(row.kind, () => <String, String>{})[row.losingId] =
          row.survivingId;
    }
    for (final byKind in result.values) {
      for (final losingId in byKind.keys.toList()) {
        var current = losingId;
        final seen = <String>{losingId};
        while (byKind[current] != null) {
          final next = byKind[current]!;
          if (!seen.add(next)) {
            throw StateError('cyclic sync alias chain');
          }
          current = next;
        }
        byKind[losingId] = current;
      }
    }
    return result;
  }

  SyncMergeCandidate _rewriteCandidate(
    SyncMergeCandidate candidate,
    Map<SyncRecordKind, Map<String, String>> aliases,
  ) {
    final byKind = aliases[candidate.blob.kind];
    final resolvedId = _resolveInMap(candidate.blob.id, byKind);
    final body = rewriteSyncInboundReferences(candidate.blob.body, aliases);
    if (candidate.blob.kind != SyncRecordKind.setting) {
      body['id'] = resolvedId;
    }
    return _candidateWithBody(
      candidate,
      resolvedId,
      body,
      updatedAt: contentHash(candidate.blob.body) == contentHash(body)
          ? null
          : nextExistenceStamp(
              now: DateTime.now().toUtc(),
              current: candidate.blob.updatedAt,
            ),
    );
  }

  SyncMergeCandidate _rewriteCandidateIdentity(
    SyncMergeCandidate candidate,
    String id,
    Map<SyncRecordKind, Map<String, String>> aliases, {
    bool preserveUpdatedAt = false,
  }) {
    final body = rewriteSyncInboundReferences(candidate.blob.body, aliases);
    if (candidate.blob.kind != SyncRecordKind.setting) body['id'] = id;
    return _candidateWithBody(
      candidate,
      id,
      body,
      updatedAt: preserveUpdatedAt
          ? candidate.blob.updatedAt
          : contentHash(candidate.blob.body) == contentHash(body)
          ? null
          : nextExistenceStamp(
              now: DateTime.now().toUtc(),
              current: candidate.blob.updatedAt,
            ),
    );
  }

  SyncMergeCandidate _candidateWithBody(
    SyncMergeCandidate candidate,
    String id,
    Map<String, Object?> body, {
    DateTime? updatedAt,
  }) {
    final blob = SyncRecordBlob(
      v: candidate.blob.v,
      kind: candidate.blob.kind,
      id: id,
      updatedAt: updatedAt ?? candidate.blob.updatedAt,
      deletedAt: candidate.blob.deletedAt,
      existenceAt: candidate.blob.existenceAt,
      body: body,
    );
    return SyncMergeCandidate(blob: blob, peerId: candidate.peerId);
  }

  SyncApplyRecord _normalizeInboundRecord(SyncApplyRecord record) {
    final body = _normalizeInboundTimestampBody(
      kind: record.address.kind,
      body: record.body,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
    );
    final sourceBlob = record.sourceBlob;
    final normalizedSourceBlob = sourceBlob == null
        ? null
        : SyncRecordBlob(
            v: sourceBlob.v,
            kind: sourceBlob.kind,
            id: sourceBlob.id,
            updatedAt: sourceBlob.updatedAt,
            deletedAt: sourceBlob.deletedAt,
            existenceAt: sourceBlob.existenceAt,
            body: _normalizeInboundTimestampBody(
              kind: sourceBlob.kind,
              body: sourceBlob.body,
              updatedAt: sourceBlob.updatedAt,
              deletedAt: sourceBlob.deletedAt,
            ),
          );
    final canonicalSourceBlob =
        sourceBlob == null ||
            canonicalJson(sourceBlob.toJson()) ==
                canonicalJson(normalizedSourceBlob!.toJson())
        ? sourceBlob
        : normalizedSourceBlob;
    if (identical(body, record.body) &&
        identical(canonicalSourceBlob, record.sourceBlob)) {
      return record;
    }
    return SyncApplyRecord(
      address: record.address,
      body: body,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      existenceAt: record.existenceAt,
      sourceBlob: canonicalSourceBlob,
    );
  }

  String _resolveInMap(String id, Map<String, String>? aliases) {
    if (aliases == null) return id;
    var current = id;
    final seen = <String>{id};
    while (aliases[current] != null) {
      final next = aliases[current]!;
      if (!seen.add(next)) throw StateError('cyclic sync alias chain');
      current = next;
    }
    return current;
  }

  Future<void> _adoptCollision({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
    required Map<SyncRecordKind, Map<String, String>> aliases,
    _NaturalKeyValue? localIdentity,
  }) async {
    if (losingId == survivingId) return;
    final target = await repositories.syncLocal.resolveAlias(
      kind: kind,
      recordId: survivingId,
    );
    final targetIdentity = await _recordIdentity(kind, target);
    if (localIdentity != null && localIdentity.id == losingId) {
      // The losing row has to stop existing under its own identity either way,
      // and which way depends only on whether `target` is already occupied —
      // not on whether `survivingId` needed an alias hop to reach it.
      // `_migrateLocalIdentity` writes the row at whatever id it is given.
      //
      // Both call sites are expected to pass a chain-terminal survivor, since
      // they also have to write the record under it. Do not turn that into an
      // `target == survivingId` gate here: a caller that forgets would fall
      // through both branches, and the rewrite below would then point join
      // rows at an ID with no row and fail the foreign key. Occupancy is the
      // property that actually decides between migrating and deleting, so it
      // is the only thing tested.
      if (targetIdentity == null) {
        await _migrateLocalIdentity(kind, losingId, target);
      } else {
        await _rewriteLocalReferences(kind, losingId, target);
        await _deleteIdentityRow(kind, losingId);
      }
    }
    await _rewriteLocalReferences(kind, losingId, target);
    await _remapPendingDeletions(
      kind: kind,
      losingId: losingId,
      survivingId: target,
      aliases: aliases,
    );
    await repositories.syncLocal.remapIdentity(
      kind: kind,
      losingId: losingId,
      survivingId: target,
    );
    _naturalKeyIndex?.removeId(kind, losingId);
    final byKind = aliases.putIfAbsent(kind, () => <String, String>{});
    for (final entry in byKind.entries.toList()) {
      if (entry.value == losingId) byKind[entry.key] = target;
    }
    byKind[losingId] = target;
  }

  Future<void> _remapPendingDeletions({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
    required Map<SyncRecordKind, Map<String, String>> aliases,
  }) async {
    if (losingId == survivingId) return;
    _remappedPendingDeletions.add((kind: kind, recordId: survivingId));
    final persistedAliases = await repositories.syncLocal.listAliases();
    final remappedIds = <String>{losingId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final alias in persistedAliases) {
        if (alias.kind == kind &&
            remappedIds.contains(alias.survivingId) &&
            remappedIds.add(alias.losingId)) {
          changed = true;
        }
      }
    }
    final pendingIds = {...remappedIds, survivingId};
    final rows = await _db.select(_db.pendingDeletions).get();
    if (rows.isEmpty) return;

    final rewriteAliases = <SyncRecordKind, Map<String, String>>{
      for (final entry in aliases.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
    for (final alias in persistedAliases) {
      rewriteAliases.putIfAbsent(
        alias.kind,
        () => <String, String>{},
      )[alias.losingId] = alias.survivingId;
    }
    rewriteAliases.putIfAbsent(kind, () => <String, String>{})[losingId] =
        survivingId;

    final candidates =
        <({SyncRecordBlob blob, DateTime tombstonedAt, String hash})>[];
    for (final row in rows) {
      final blob = decodeSyncRecordBlob(row.tombstoneBlob);
      if (blob.kind != row.kind ||
          blob.id != row.recordId ||
          blob.deletedAt == null ||
          sha256Hex(encodeSyncRecordBlobUtf8(blob)) != row.tombstoneHash) {
        throw StateError(
          'pending tombstone does not match its stored identity or hash',
        );
      }
      final remapOwnIdentity =
          row.kind == kind && pendingIds.contains(row.recordId);
      final body = Map<String, Object?>.from(blob.body);
      if (remapOwnIdentity && kind != SyncRecordKind.setting) {
        body['id'] = survivingId;
      }
      final rewrittenBody = rewriteSyncInboundReferences(body, rewriteAliases);
      final remappedId = remapOwnIdentity && kind != SyncRecordKind.setting
          ? survivingId
          : blob.id;
      final remappedUpdatedAt =
          contentHash(blob.body) == contentHash(rewrittenBody)
          ? blob.updatedAt
          : nextExistenceStamp(
              now: DateTime.now().toUtc(),
              current: blob.updatedAt,
            );
      final remapped = SyncRecordBlob(
        v: blob.v,
        kind: blob.kind,
        id: remappedId,
        updatedAt: remappedUpdatedAt,
        deletedAt: blob.deletedAt,
        existenceAt: blob.existenceAt,
        body: rewrittenBody,
      );
      final remappedHash = sha256Hex(encodeSyncRecordBlobUtf8(remapped));
      if (remapOwnIdentity) {
        candidates.add((
          blob: remapped,
          tombstonedAt: row.tombstonedAt,
          hash: remappedHash,
        ));
      } else if (remappedHash != row.tombstoneHash) {
        await repositories.syncLocal.upsertPendingDeletion(
          kind: row.kind,
          recordId: row.recordId,
          tombstonedAt: row.tombstonedAt,
          tombstoneHash: remappedHash,
          tombstoneBlob: encodeSyncRecordBlob(remapped),
        );
      }
    }
    if (candidates.isEmpty) return;
    candidates.sort((a, b) {
      final existence = a.blob.existenceAt.compareTo(b.blob.existenceAt);
      if (existence != 0) return existence;
      final updated = a.blob.updatedAt.compareTo(b.blob.updatedAt);
      if (updated != 0) return updated;
      final tombstoned = a.tombstonedAt.compareTo(b.tombstonedAt);
      if (tombstoned != 0) return tombstoned;
      return a.hash.compareTo(b.hash);
    });
    final selected = candidates.last;
    for (final chunk in _chunked(pendingIds, 500)) {
      await (_db.delete(_db.pendingDeletions)..where(
            (row) => row.kind.equals(kind.name) & row.recordId.isIn(chunk),
          ))
          .go();
    }
    await _db
        .into(_db.pendingDeletions)
        .insert(
          PendingDeletionsCompanion.insert(
            kind: kind,
            recordId: survivingId,
            tombstonedAt: selected.tombstonedAt,
            tombstoneHash: selected.hash,
            tombstoneBlob: encodeSyncRecordBlob(selected.blob),
          ),
        );
  }

  Future<_NaturalKeyValue?> _recordIdentity(
    SyncRecordKind kind,
    String id,
  ) async {
    switch (kind) {
      case SyncRecordKind.choreographer:
        final row = await (_db.select(
          _db.choreographers,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: null,
                deleted: row.deletedAt != null,
                shareable: true,
              );
      case SyncRecordKind.tag:
        final row = await (_db.select(
          _db.tags,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: null,
                deleted: row.deletedAt != null,
                shareable: true,
              );
      case SyncRecordKind.customFieldDef:
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: row.type.name,
                deleted: row.deletedAt != null,
                shareable: row.shareable,
              );
      case SyncRecordKind.difficultyLevel:
        final row = await (_db.select(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: null,
                deleted: row.deletedAt != null,
                shareable: true,
              );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return null;
    }
  }

  Future<_NaturalKeyValue?> _naturalKeyRow(
    SyncRecordKind kind,
    String key,
  ) async {
    final indexed = _naturalKeyIndex?.lookup(kind, key);
    if (_naturalKeyIndex != null) return indexed;
    switch (kind) {
      case SyncRecordKind.choreographer:
        final rows = await _db.select(_db.choreographers).get();
        for (final row in rows) {
          if (normalizeShareableText(row.name).toLowerCase() == key) {
            return (
              id: row.id,
              type: null,
              deleted: row.deletedAt != null,
              shareable: true,
            );
          }
        }
      case SyncRecordKind.tag:
        final rows = await _db.select(_db.tags).get();
        for (final row in rows) {
          if (normalizeShareableText(row.name).toLowerCase() == key) {
            return (
              id: row.id,
              type: null,
              deleted: row.deletedAt != null,
              shareable: true,
            );
          }
        }
      case SyncRecordKind.customFieldDef:
        final rows = await _db.select(_db.customFieldDefs).get();
        for (final row in rows) {
          if (normalizeShareableText(row.key).toLowerCase() == key) {
            return (
              id: row.id,
              type: row.type.name,
              deleted: row.deletedAt != null,
              shareable: row.shareable,
            );
          }
        }
      case SyncRecordKind.difficultyLevel:
        final rows = await _db.select(_db.difficultyLevels).get();
        for (final row in rows) {
          if (normalizeShareableText(row.label).toLowerCase() == key) {
            return (
              id: row.id,
              type: null,
              deleted: row.deletedAt != null,
              shareable: true,
            );
          }
        }
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        break;
    }
    return null;
  }

  String? _customFieldType(Map<String, Object?> body) =>
      body['type'] is String ? body['type']! as String : null;

  Future<SyncMergeCandidate?> _localNaturalCandidate({
    required SyncRecordKind kind,
    required String id,
  }) async {
    final body = await read((kind: kind, recordId: id));
    if (body == null) return null;
    final metadata = await _naturalRecordMetadata(kind, id);
    if (metadata == null) return null;
    final entity = _decodeEntity(kind, body);
    return SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: metadata.updatedAt,
        deletedAt: metadata.deletedAt,
        existenceAt: metadata.existenceAt,
        body: syncBodyForEntity(kind, entity),
      ),
    );
  }

  /// Whether [candidate] would actually resolve a baseline-absent live local
  /// row out of existence.
  ///
  /// §6.6 conditions its guard on *step 2 resolving the survivor to
  /// non-existence*, and step 2 decides existence by the greater
  /// `existenceAt`. Firing on "inbound is a tombstone and the local row is
  /// live" alone queued pairs that step 2 would have kept alive, so no alias
  /// was ever written, the collision was re-derived every pass, and the user
  /// was handed a review whose Merge action `resolveReviewQueue` is bound to
  /// refuse (it rejects a local `existence_at` newer than the candidate's).
  ///
  /// An equal stamp is deliberately not suppressed: that is a genuine tie
  /// between two floored transitions, which §6.4 resolves to the tombstone
  /// silently. Only the unequal comparison against a creation stamp that was
  /// never floored is the one the guard exists for.
  Future<bool> _tombstoneOutranksLocalCreation(
    SyncRecordKind kind,
    String incumbentId,
    SyncRecordBlob candidate,
  ) async {
    final metadata = await _naturalRecordMetadata(kind, incumbentId);
    if (metadata == null) return true;
    return candidate.existenceAt.isAfter(metadata.existenceAt);
  }

  Future<({DateTime updatedAt, DateTime existenceAt, DateTime? deletedAt})?>
  _naturalRecordMetadata(SyncRecordKind kind, String id) async {
    switch (kind) {
      case SyncRecordKind.choreographer:
        final row = await (_db.select(
          _db.choreographers,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.tag:
        final row = await (_db.select(
          _db.tags,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.customFieldDef:
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.difficultyLevel:
        final row = await (_db.select(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return null;
    }
  }

  Future<SyncMergeCandidate?> _reconcileNaturalKeyCollision({
    required SyncMergeCandidate candidate,
    required SyncMergeCandidate local,
    required String survivorId,
  }) async {
    final incomingExistenceWins =
        candidate.blob.existenceAt.isAfter(local.blob.existenceAt) ||
        (candidate.blob.existenceAt == local.blob.existenceAt &&
            candidate.blob.deletedAt != null &&
            local.blob.deletedAt == null);
    final localExistenceWins =
        local.blob.existenceAt.isAfter(candidate.blob.existenceAt) ||
        (candidate.blob.existenceAt == local.blob.existenceAt &&
            local.blob.deletedAt != null &&
            candidate.blob.deletedAt == null);
    final existenceSource = incomingExistenceWins
        ? candidate
        : localExistenceWins
        ? local
        : candidate;
    final winningDeleted = existenceSource.blob.deletedAt != null;
    final contentCandidates = [
      if ((candidate.blob.deletedAt != null) == winningDeleted) candidate,
      if ((local.blob.deletedAt != null) == winningDeleted) local,
    ];
    final contentSource = _newerNaturalContent(
      candidate: contentCandidates.first,
      other: contentCandidates.length == 1 ? null : contentCandidates.last,
    );
    if (contentSource == null) {
      await _enqueueCollisionReview(
        candidate,
        local.blob.id,
        reason:
            'natural-key collision has different bodies at the same '
            'updatedAt',
      );
      return null;
    }
    final body = Map<String, Object?>.from(contentSource.blob.body)
      ..['id'] = survivorId;
    return SyncMergeCandidate(
      blob: SyncRecordBlob(
        v: contentSource.blob.v,
        kind: candidate.blob.kind,
        id: survivorId,
        updatedAt: contentSource.blob.updatedAt,
        deletedAt: existenceSource.blob.deletedAt,
        existenceAt: candidate.blob.existenceAt.isAfter(local.blob.existenceAt)
            ? candidate.blob.existenceAt
            : local.blob.existenceAt,
        body: body,
      ),
      peerId: contentSource.peerId,
    );
  }

  SyncMergeCandidate? _newerNaturalContent({
    required SyncMergeCandidate candidate,
    required SyncMergeCandidate? other,
  }) {
    if (other == null) return candidate;
    final comparison = candidate.blob.updatedAt.compareTo(other.blob.updatedAt);
    if (comparison > 0) return candidate;
    if (comparison < 0) return other;
    final candidateBody = Map<String, Object?>.from(candidate.blob.body)
      ..remove('id');
    final otherBody = Map<String, Object?>.from(other.blob.body)..remove('id');
    return contentHash(candidateBody) == contentHash(otherBody)
        ? candidate
        : null;
  }

  String? _canonicalDifficultyId(
    String key, {
    required String candidateId,
    String? incumbentId,
  }) {
    final incumbent = DifficultyLevel.knownForId(incumbentId);
    if (incumbent != null) return incumbent.id;
    final candidate = DifficultyLevel.knownForId(candidateId);
    if (candidate != null) return candidate.id;
    for (final level in DifficultyLevel.shipped) {
      if (normalizeShareableText(level.label).toLowerCase() == key) {
        return level.id;
      }
    }
    return null;
  }

  Future<SyncMergeCandidate?> _reconcileCustomFieldTypeMismatch(
    SyncMergeCandidate candidate,
    _NaturalKeyValue incumbent,
  ) async {
    final incomingWins = candidate.blob.id.compareTo(incumbent.id) < 0;
    final losingId = incomingWins ? incumbent.id : candidate.blob.id;
    final key = candidate.blob.body['key'];
    if (key is! String) return null;
    final shortKey = syncCustomFieldSuffix(key, losingId, full: false);
    final fullKey = syncCustomFieldSuffix(key, losingId, full: true);
    final suffix =
        await _naturalKeyRow(
              SyncRecordKind.customFieldDef,
              shortKey.toLowerCase(),
            ) ==
            null
        ? shortKey
        : await _naturalKeyRow(
                SyncRecordKind.customFieldDef,
                fullKey.toLowerCase(),
              ) ==
              null
        ? fullKey
        : null;
    if (suffix == null) {
      await _enqueueCollisionReview(
        candidate,
        incumbent.id,
        reason: 'custom-field type mismatch has no deterministic free key',
      );
      return null;
    }
    if (incomingWins) {
      await _renameLocalCustomField(incumbent.id, suffix);
      return candidate;
    }
    final body = rewriteSyncInboundReferences(
      candidate.blob.body,
      const <SyncRecordKind, Map<String, String>>{},
    )..['key'] = suffix;
    final stamp = nextExistenceStamp(
      now: DateTime.now().toUtc(),
      current: candidate.blob.updatedAt,
    );
    return _candidateWithBody(
      candidate,
      candidate.blob.id,
      body,
      updatedAt: stamp,
    );
  }

  /// Frees a shareable inbound definition's key by renaming the colliding
  /// **private local** definition, per §6.6's shareability rule.
  ///
  /// Returns whether the inbound candidate may now be applied unchanged. The
  /// suffix derives from the private definition's own UUID and is checked for
  /// occupancy the same way [_reconcileCustomFieldTypeMismatch] checks its
  /// own; when neither the eight-hex nor the full form is free there is no
  /// deterministic answer, so the collision keeps its existing review-queue
  /// fallback.
  ///
  /// The rename bumps the private row's `updatedAt`, which is inert: a private
  /// definition is projected to an empty body and so never enters the
  /// publication.
  Future<bool> _renameLocalPrivateCustomField(
    SyncMergeCandidate candidate,
    _NaturalKeyValue incumbent,
  ) async {
    final key = candidate.blob.body['key'];
    if (key is! String) return false;
    final shortKey = syncCustomFieldSuffix(key, incumbent.id, full: false);
    final fullKey = syncCustomFieldSuffix(key, incumbent.id, full: true);
    final suffix =
        await _naturalKeyRow(
              SyncRecordKind.customFieldDef,
              shortKey.toLowerCase(),
            ) ==
            null
        ? shortKey
        : await _naturalKeyRow(
                SyncRecordKind.customFieldDef,
                fullKey.toLowerCase(),
              ) ==
              null
        ? fullKey
        : null;
    if (suffix == null) {
      await _enqueueCollisionReview(
        candidate,
        incumbent.id,
        reason:
            'shareability mismatch cannot reconcile a private '
            'custom-field definition',
      );
      return false;
    }
    await _renameLocalCustomField(incumbent.id, suffix);
    return true;
  }

  /// Queues, or re-queues, one collision for the persisted review surface.
  ///
  /// The row carries the local wire hash captured at enqueue so
  /// [resolveReviewQueue] can refuse a decision taken against a record the user
  /// has since edited. That guard is only safe because this re-queues the row
  /// whenever either side has moved: `insertOrIgnore` alone would pin the first
  /// observation forever and leave an actionable row no resolution could ever
  /// satisfy. An unchanged row keeps its original `queuedAt` so re-observing
  /// the same collision does not reorder the queue.
  Future<void> _enqueueCollisionReview(
    SyncMergeCandidate candidate,
    String counterpartId, {
    String? recordId,
    required String reason,
  }) async {
    final queuedRecordId = recordId ?? candidate.blob.id;
    // Only the reasons whose resolution re-validates staleness record a local
    // hash; the rest stay NULL until they gain an action. For a §6.6 step-1
    // reason `queuedRecordId` is the candidate's own id — the local row the
    // peer's update targets, and the one this pass deliberately does not write
    // — so the hash captured here still describes that row when the user
    // eventually decides.
    final localHash =
        reason == syncBaselineAbsenceTombstoneReason ||
            syncNaturalKeyRenameCollisionReasons.contains(reason)
        ? (await _localNaturalCandidate(
            kind: candidate.blob.kind,
            id: queuedRecordId,
          ))?.wireHash
        : null;
    final candidateBlob = encodeSyncRecordBlob(candidate.blob);
    final existing = await repositories.syncLocal.getReviewQueue(
      kind: candidate.blob.kind,
      recordId: queuedRecordId,
      counterpartId: counterpartId,
    );
    if (existing != null) {
      if (existing.reason == reason &&
          existing.candidateBlob == candidateBlob &&
          existing.candidateHash == candidate.wireHash &&
          existing.localHash == localHash) {
        return;
      }
      await repositories.syncLocal.deleteReview(
        kind: candidate.blob.kind,
        recordId: queuedRecordId,
        counterpartId: counterpartId,
      );
    }
    await repositories.syncLocal.enqueueReview(
      kind: candidate.blob.kind,
      recordId: queuedRecordId,
      counterpartId: counterpartId,
      reason: reason,
      candidateBlob: candidateBlob,
      candidateHash: candidate.wireHash,
      localHash: localHash,
      queuedAt: DateTime.now().toUtc(),
    );
  }

  Future<bool> _guardReconciliationTarget({
    required SyncRecordKind kind,
    required String recordId,
    required Map<SyncRecordAddress, String?>? expectedWireHashes,
    required List<SyncReport> reports,
  }) async {
    final address = (kind: kind, recordId: recordId);
    if (expectedWireHashes == null ||
        !expectedWireHashes.containsKey(address)) {
      return true;
    }
    final expected = expectedWireHashes[address];
    final current = await _localNaturalCandidate(kind: kind, id: recordId);
    if (current?.wireHash == expected) return true;
    reports.add(
      SyncReport(
        code: SyncReportCode.concurrentLocalChange,
        kind: kind,
        recordId: recordId,
        message:
            'Local reconciliation target changed while sync was preparing '
            'its inbound update.',
      ),
    );
    return false;
  }

  Future<void> _renameLocalCustomField(String id, String newKey) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final stamp = nextExistenceStamp(
      now: DateTime.now().toUtc(),
      current: row.updatedAt,
    );
    await (_db.update(
      _db.customFieldDefs,
    )..where((table) => table.id.equals(id))).write(
      CustomFieldDefsCompanion(key: Value(newKey), updatedAt: Value(stamp)),
    );
    _naturalKeyIndex?.replace(
      kind: SyncRecordKind.customFieldDef,
      id: id,
      key: normalizeShareableText(newKey).toLowerCase(),
      type: row.type.name,
      deleted: row.deletedAt != null,
      shareable: row.shareable,
    );
  }

  Future<String> _temporaryNaturalKey(
    SyncRecordKind kind,
    String losingId,
    String survivingId,
  ) async {
    final base = '__sync_${losingId}_$survivingId';
    var candidate = base;
    var suffix = 2;
    while (await _naturalKeyRow(
          kind,
          normalizeShareableText(candidate).toLowerCase(),
        ) !=
        null) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  /// Moves a local losing row onto the deterministic survivor identity before
  /// the inbound candidate is written. The temporary natural key keeps the
  /// unique index valid while the new parent row is inserted.
  Future<void> _migrateLocalIdentity(
    SyncRecordKind kind,
    String losingId,
    String survivingId,
  ) async {
    if (losingId == survivingId) return;
    final temporaryNaturalKey = await _temporaryNaturalKey(
      kind,
      losingId,
      survivingId,
    );
    switch (kind) {
      case SyncRecordKind.choreographer:
        final row = await (_db.select(
          _db.choreographers,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.choreographers,
        )..where((table) => table.id.equals(losingId))).write(
          ChoreographersCompanion(
            name: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.choreographers)
            .insert(
              ChoreographersCompanion.insert(
                id: survivingId,
                name: row.name,
                website: Value(row.website),
                notes: Value(row.notes),
                email: Value(row.email),
                location: Value(row.location),
                deceased: Value(row.deceased),
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.name).toLowerCase(),
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        );
      case SyncRecordKind.tag:
        final row = await (_db.select(
          _db.tags,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.tags,
        )..where((table) => table.id.equals(losingId))).write(
          TagsCompanion(
            name: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.tags)
            .insert(
              TagsCompanion.insert(
                id: survivingId,
                name: row.name,
                color: Value(row.color),
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.name).toLowerCase(),
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        );
      case SyncRecordKind.customFieldDef:
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(losingId))).write(
          CustomFieldDefsCompanion(
            key: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.customFieldDefs)
            .insert(
              CustomFieldDefsCompanion.insert(
                id: survivingId,
                key: row.key,
                label: row.label,
                type: row.type,
                choicesJson: Value(row.choicesJson),
                showInList: Value(row.showInList),
                searchable: Value(row.searchable),
                shareable: Value(row.shareable),
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.key).toLowerCase(),
          type: row.type.name,
          deleted: row.deletedAt != null,
          shareable: row.shareable,
        );
      case SyncRecordKind.difficultyLevel:
        final row = await (_db.select(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(losingId))).write(
          DifficultyLevelsCompanion(
            label: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.difficultyLevels)
            .insert(
              DifficultyLevelsCompanion.insert(
                id: survivingId,
                label: row.label,
                position: row.position,
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.label).toLowerCase(),
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
    await _rewriteLocalReferences(kind, losingId, survivingId);
    await _deleteIdentityRow(kind, losingId);
    _naturalKeyIndex?.removeId(kind, losingId);
  }

  Future<void> _deleteIdentityRow(SyncRecordKind kind, String id) async {
    switch (kind) {
      case SyncRecordKind.choreographer:
        await (_db.delete(
          _db.choreographers,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.tag:
        await (_db.delete(
          _db.tags,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.customFieldDef:
        await (_db.delete(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.difficultyLevel:
        await (_db.delete(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.dance:
        for (final table in const ['dance_fts', 'dance_substring_fts']) {
          await _db.customStatement('DELETE FROM $table WHERE dance_id = ?', [
            id,
          ]);
        }
        await (_db.delete(
          _db.dances,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
  }

  Future<void> _rewriteLocalReferences(
    SyncRecordKind kind,
    String losingId,
    String survivingId,
  ) async {
    if (losingId == survivingId) return;
    final affectedDances = <String>{};
    switch (kind) {
      case SyncRecordKind.choreographer:
        final rows = await (_db.select(
          _db.danceAuthors,
        )..where((row) => row.choreographerId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.danceAuthors)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.choreographerId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.danceAuthors)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.choreographerId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.danceAuthors)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.choreographerId.equals(losingId),
                ))
                .write(
                  DanceAuthorsCompanion(choreographerId: Value(survivingId)),
                );
          }
        }
      case SyncRecordKind.tag:
        final rows = await (_db.select(
          _db.danceTags,
        )..where((row) => row.tagId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.danceTags)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.tagId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.danceTags)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.tagId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.danceTags)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.tagId.equals(losingId),
                ))
                .write(DanceTagsCompanion(tagId: Value(survivingId)));
          }
        }
      case SyncRecordKind.publishedSource:
        final rows = await (_db.select(
          _db.danceSources,
        )..where((row) => row.sourceId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.danceSources)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.sourceId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.danceSources)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.sourceId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.danceSources)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.sourceId.equals(losingId),
                ))
                .write(DanceSourcesCompanion(sourceId: Value(survivingId)));
          }
        }
      case SyncRecordKind.customFieldDef:
        final rows = await (_db.select(
          _db.customFieldValues,
        )..where((row) => row.fieldId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.customFieldValues)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.fieldId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.customFieldValues)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.fieldId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.customFieldValues)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.fieldId.equals(losingId),
                ))
                .write(CustomFieldValuesCompanion(fieldId: Value(survivingId)));
          }
        }
      case SyncRecordKind.difficultyLevel:
        final rows = await (_db.select(
          _db.dances,
        )..where((row) => row.levelId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.id));
        for (final row in rows) {
          await (_db.update(
            _db.dances,
          )..where((table) => table.id.equals(row.id))).write(
            DancesCompanion(
              levelId: Value(survivingId),
              updatedAt: Value(row.updatedAt),
            ),
          );
        }
      case SyncRecordKind.dance:
        final slotRows = await (_db.select(
          _db.programSlots,
        )..where((row) => row.danceId.equals(losingId))).get();
        final affectedPrograms = slotRows.map((row) => row.programId).toSet();
        await (_db.update(_db.programSlots)
              ..where((row) => row.danceId.equals(losingId)))
            .write(ProgramSlotsCompanion(danceId: Value(survivingId)));

        final linkOwners = await (_db.select(
          _db.danceLinks,
        )..where((row) => row.targetDanceId.equals(losingId))).get();
        final linkOwnerIds = linkOwners
            .map((row) => row.danceId)
            .where((id) => id != losingId)
            .toSet();
        await (_db.update(_db.danceLinks)
              ..where((row) => row.targetDanceId.equals(losingId)))
            .write(DanceLinksCompanion(targetDanceId: Value(survivingId)));

        final now = DateTime.now().toUtc();
        for (final programId in affectedPrograms) {
          final row = await (_db.select(
            _db.programs,
          )..where((table) => table.id.equals(programId))).getSingleOrNull();
          if (row == null) continue;
          await (_db.update(
            _db.programs,
          )..where((table) => table.id.equals(programId))).write(
            ProgramsCompanion(
              updatedAt: Value(
                nextExistenceStamp(now: now, current: row.updatedAt),
              ),
            ),
          );
        }
        affectedDances.addAll(linkOwnerIds);
      case SyncRecordKind.program:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
    if (affectedDances.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final danceId in affectedDances) {
      final row = await (_db.select(
        _db.dances,
      )..where((table) => table.id.equals(danceId))).getSingleOrNull();
      if (row == null) continue;
      await (_db.update(
        _db.dances,
      )..where((table) => table.id.equals(danceId))).write(
        DancesCompanion(
          updatedAt: Value(
            nextExistenceStamp(now: now, current: row.updatedAt),
          ),
        ),
      );
    }
  }

  @override
  Future<void> write(SyncApplyRecord record) async {
    await writeWithReport(record);
  }

  @override
  Future<SyncReport?> validateInboundReferences(
    SyncApplyRecord record, {
    Set<SyncRecordAddress> inboundLiveAddresses = const {},
    Set<SyncRecordAddress> inboundAddresses = const {},
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords = const {},
  }) async {
    record = _normalizeInboundRecord(record);
    if (record.address.kind == SyncRecordKind.setting) return null;
    final Object entity;
    try {
      entity = _decodeEntity(record.address.kind, record.body);
    } on FormatException catch (error) {
      return _malformedReferenceReport(record, error.message);
    } on ArgumentError catch (error) {
      return _malformedReferenceReport(record, '$error');
    } on Object catch (error) {
      return _malformedReferenceReport(record, '$error');
    }
    final classificationIssue = await _invalidCustomFieldClassification(
      record,
      entity,
      inboundAddresses: inboundAddresses,
      inboundRecords: inboundRecords,
    );
    if (classificationIssue != null) {
      return SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: record.address.kind,
        recordId: record.address.recordId,
        message: classificationIssue,
      );
    }
    // A tombstone may retain joins to other tombstones in the same batch. The
    // live-record guard still applies, but deletion records resolve references
    // against any existing row so their existence transition can converge.
    final allowTombstonedReferences = record.deletedAt != null;
    final referenceInboundLiveAddresses = allowTombstonedReferences
        ? inboundAddresses
        : inboundLiveAddresses;
    final dependentIndex = _dependentIndexFor(inboundRecords);

    final dependentRowIssue = switch (record.address.kind) {
      SyncRecordKind.dance => await _invalidDanceDependentRows(
        entity as Dance,
        dependentIndex: dependentIndex,
      ),
      SyncRecordKind.program => await _invalidProgramDependentRows(
        entity as Program,
        dependentIndex: dependentIndex,
      ),
      _ => null,
    };
    if (dependentRowIssue != null) {
      return SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: record.address.kind,
        recordId: record.address.recordId,
        message: dependentRowIssue,
      );
    }

    final missing = switch (record.address.kind) {
      SyncRecordKind.dance => await _missingDanceReference(
        entity as Dance,
        inboundLiveAddresses: referenceInboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        inboundRecords: inboundRecords,
        allowTombstonedReferences: allowTombstonedReferences,
      ),
      SyncRecordKind.program => await _missingProgramReference(
        entity as Program,
        inboundLiveAddresses: referenceInboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        allowTombstonedReferences: allowTombstonedReferences,
      ),
      _ => null,
    };
    return missing == null
        ? null
        : SyncReport(
            code: SyncReportCode.unresolvedReference,
            kind: record.address.kind,
            recordId: record.address.recordId,
            message: missing,
          );
  }

  /// Cancels a deferred deletion that an inbound revival outranks.
  ///
  /// §6.8 keeps a tombstone this device cannot apply — the entity is still
  /// cited — as a pending row, and the row it names stays live meanwhile. A
  /// peer that revives the record stamps above the tombstone it revived by
  /// construction (§6.4), so once such a revival wins the existence comparison
  /// the deferred deletion has been overtaken and must go: leaving the row in
  /// place would let the deletion land anyway the moment the last citation
  /// clears, silently undoing a revival that outranked it.
  ///
  /// The comparison is made here rather than assumed from the caller, so every
  /// path that writes a record holds it — including the ones that reach this
  /// writer without merge planning. Equal stamps resolve to the tombstone, per
  /// §6.4, so the advance must be strict.
  Future<void> _cancelOutrankedPendingDeletion(SyncApplyRecord record) async {
    if (record.deletedAt != null) return;
    if (_remappedPendingDeletions.contains(record.address)) return;
    final pending = await repositories.syncLocal.getPendingDeletion(
      kind: record.address.kind,
      recordId: record.address.recordId,
    );
    if (pending == null) return;
    final DateTime tombstonedExistence;
    try {
      tombstonedExistence = decodeSyncRecordBlob(
        pending.tombstoneBlob,
      ).existenceAt;
    } on Object {
      // A tombstone blob that will not decode cannot be compared against, and
      // `_revalidatePendingDeletions` owns that failure. Leave it alone.
      return;
    }
    if (!record.existenceAt.isAfter(tombstonedExistence)) return;
    await repositories.syncLocal.deletePendingDeletion(
      kind: record.address.kind,
      recordId: record.address.recordId,
    );
  }

  @override
  Future<SyncReport?> writeWithReport(SyncApplyRecord record) async {
    record = _normalizeInboundRecord(record);
    final kind = record.address.kind;
    if (record.deletedAt != null &&
        await _hasCitation(
          kind,
          record.address.recordId,
          ignoreInboundTombstones: true,
        )) {
      await _storePendingDeletion(record);
      return null;
    }
    if (kind == SyncRecordKind.setting) {
      final value = record.body['value'];
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: record.address.recordId,
              valueJson: jsonEncode(normalizeShareableJson(value)),
              updatedAt: Value(record.updatedAt),
              deletedAt: Value(record.deletedAt),
              existenceAt: Value(record.existenceAt),
            ),
          );
      return null;
    }

    final Object entity;
    try {
      entity = _decodeEntity(kind, record.body);
    } on Object catch (error) {
      return _malformedReferenceReport(record, '$error');
    }
    SyncReport? report;
    Object entityToWrite = entity;
    if (kind == SyncRecordKind.program) {
      final program = entity as Program;
      if (program.venueId != null && !(await _isLiveVenue(program.venueId!))) {
        // I1 forbids changing a peer's serialised content without advancing
        // `updatedAt` (§6.5), so the dangling reference is stored verbatim —
        // not nulled — and only reported. `programs.venue_id` is not a
        // database foreign key, so a dangling value can be persisted; see
        // `ProgramRepository._upsert` for the corresponding write-path
        // tolerance and every reader of the column for null-venue handling.
        report = SyncReport(
          code: SyncReportCode.unresolvedReference,
          kind: kind,
          recordId: record.address.recordId,
          message: 'Program venue reference is missing locally.',
        );
      }
    }

    switch (kind) {
      case SyncRecordKind.dance:
        await repositories.dances.writeFromSync(entityToWrite as Dance);
      case SyncRecordKind.program:
        await repositories.programs.writeFromSync(entityToWrite as Program);
      case SyncRecordKind.choreographer:
        await repositories.choreographers.writeFromSync(
          entityToWrite as Choreographer,
          at: record.updatedAt,
        );
      case SyncRecordKind.tag:
        await repositories.tags.writeFromSync(
          entityToWrite as Tag,
          at: record.updatedAt,
        );
      case SyncRecordKind.publishedSource:
        await repositories.publishedSources.writeFromSync(
          entityToWrite as PublishedSource,
          at: record.updatedAt,
        );
      case SyncRecordKind.customFieldDef:
        await repositories.customFieldDefs.writeFromSync(
          entityToWrite as CustomFieldDef,
          at: record.updatedAt,
        );
      case SyncRecordKind.difficultyLevel:
        await repositories.difficultyLevels.writeFromSync(
          entityToWrite as DifficultyLevel,
          at: record.updatedAt,
        );
      case SyncRecordKind.venue:
        await repositories.venues.writeFromSync(
          entityToWrite as Venue,
          at: record.updatedAt,
        );
      case SyncRecordKind.setting:
        throw StateError('settings are handled above');
    }
    await _restoreTimestamps(
      kind: kind,
      id: record.address.recordId,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      existenceAt: record.existenceAt,
    );
    // Last, once the record has actually landed. Cancelling earlier discarded
    // the deferred tombstone even when the write was then reported and skipped
    // — a malformed body, a held natural key — and the deletion could never
    // apply again, because nothing else remembers it.
    await _cancelOutrankedPendingDeletion(record);
    return report;
  }

  @override
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) async {
    record = _normalizeInboundRecord(record);
    if (record.deletedAt != null &&
        await _hasCitation(
          record.address.kind,
          record.address.recordId,
          ignoreInboundTombstones: true,
        )) {
      await _storePendingDeletion(record);
      _pendingParentWrites.add(record.address);
      return null;
    }
    _pendingParentWrites.remove(record.address);
    final kind = record.address.kind;
    if (kind != SyncRecordKind.dance && kind != SyncRecordKind.program) {
      return writeWithReport(record);
    }

    final prepared = await _prepareEntity(record);
    _deferredEntities[record.address] = prepared.entity;
    switch (kind) {
      case SyncRecordKind.dance:
        await repositories.dances.writeFromSyncParent(prepared.entity as Dance);
      case SyncRecordKind.program:
        await repositories.programs.writeFromSyncParent(
          prepared.entity as Program,
        );
      case SyncRecordKind.setting:
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
        throw StateError('unexpected non-parent sync kind: $kind');
    }
    return prepared.report;
  }

  /// Captures the parent row of a two-phase kind so a failed join write can
  /// put it back. Only `dance` and `program` have a join phase; every other
  /// kind is written whole by `writeWithReport`, so there is nothing to undo
  /// and this returns `null` for them.
  @override
  Future<Object?> capturePreImage(SyncRecordAddress address) async {
    switch (address.kind) {
      case SyncRecordKind.dance:
        final row =
            await (_db.select(_db.dances)
                  ..where((table) => table.id.equals(address.recordId)))
                .getSingleOrNull();
        return _ParentPreImage(dance: row?.toCompanion(false));
      case SyncRecordKind.program:
        final row =
            await (_db.select(_db.programs)
                  ..where((table) => table.id.equals(address.recordId)))
                .getSingleOrNull();
        return _ParentPreImage(program: row?.toCompanion(false));
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return null;
    }
  }

  /// Puts back what [capturePreImage] took, deleting the row when the record
  /// did not exist then.
  ///
  /// The row is restored directly rather than through the repository writers:
  /// this is an undo, so it must reinstate exactly the captured columns
  /// without re-running normalisation, existence seeding or the reference
  /// guards — any of which could fail here, or quietly write something other
  /// than what was captured. Deleting cascades the join rows, which is right:
  /// a record that did not exist before this batch has none of its own, and
  /// the failed join savepoint wrote none.
  @override
  Future<void> restorePreImage(
    SyncRecordAddress address,
    Object? preImage,
  ) async {
    if (preImage is! _ParentPreImage) return;
    switch (address.kind) {
      case SyncRecordKind.dance:
        final companion = preImage.dance;
        if (companion == null) {
          await (_db.delete(
            _db.dances,
          )..where((table) => table.id.equals(address.recordId))).go();
        } else {
          // sync-invariant-exclusion: apply-undo restores the captured row verbatim.
          await _db.into(_db.dances).insertOnConflictUpdate(companion);
        }
      case SyncRecordKind.program:
        final companion = preImage.program;
        if (companion == null) {
          await (_db.delete(
            _db.programs,
          )..where((table) => table.id.equals(address.recordId))).go();
        } else {
          // sync-invariant-exclusion: apply-undo restores the captured row verbatim.
          await _db.into(_db.programs).insertOnConflictUpdate(companion);
        }
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
    _deferredEntities.remove(address);
  }

  @override
  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) async {
    if (_pendingParentWrites.remove(record.address)) return null;
    if (record.address.kind != SyncRecordKind.dance &&
        record.address.kind != SyncRecordKind.program) {
      return null;
    }
    // One savepoint over the relations, the timestamp restore and the pending
    // cancellation. The engine's undo restores the parent only, which is sound
    // exactly when a throw from here leaves none of this behind: previously a
    // failure in `_restoreTimestamps` kept the relation rows the writer had
    // already committed, and the undo then put the old parent back beside
    // them — the hybrid it exists to prevent.
    return _db.transaction(() => _writeJoins(record));
  }

  Future<SyncReport?> _writeJoins(SyncApplyRecord record) async {
    final entity = _deferredEntities.remove(record.address);
    if (entity == null) {
      throw StateError(
        'missing deferred sync parent for ${record.address.kind.name}:'
        '${record.address.recordId}',
      );
    }
    switch (record.address.kind) {
      case SyncRecordKind.dance:
        await repositories.dances.writeFromSyncRelations(entity as Dance);
      case SyncRecordKind.program:
        await repositories.programs.writeFromSyncRelations(entity as Program);
      case SyncRecordKind.setting:
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
        return null;
    }
    await _restoreTimestamps(
      kind: record.address.kind,
      id: record.address.recordId,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      existenceAt: record.existenceAt,
    );
    // A dance or program is complete only once its joins are in, so this is
    // where its deferred tombstone may be cancelled — not at the parent write,
    // which the joins phase can still undo.
    await _cancelOutrankedPendingDeletion(record);
    return null;
  }

  Future<void> _storePendingDeletion(SyncApplyRecord record) async {
    final blob =
        record.sourceBlob ??
        SyncRecordBlob(
          kind: record.address.kind,
          id: record.address.recordId,
          updatedAt: record.updatedAt,
          deletedAt: record.deletedAt,
          existenceAt: record.existenceAt,
          body: record.body,
        );
    final encoded = encodeSyncRecordBlob(blob);
    await repositories.syncLocal.upsertPendingDeletion(
      kind: record.address.kind,
      recordId: record.address.recordId,
      tombstonedAt: record.deletedAt!,
      tombstoneHash: sha256Hex(utf8.encode(encoded)),
      tombstoneBlob: encoded,
    );
  }

  Future<({Object entity, SyncReport? report})> _prepareEntity(
    SyncApplyRecord record,
  ) async {
    record = _normalizeInboundRecord(record);
    final kind = record.address.kind;
    final entity = _decodeEntity(kind, record.body);
    if (kind != SyncRecordKind.program) {
      return (entity: entity, report: null);
    }
    final program = entity as Program;
    if (program.venueId == null || await _isLiveVenue(program.venueId!)) {
      return (entity: program, report: null);
    }
    // See `writeWithReport`: the peer's body — including the dangling
    // `venueId` — is stored verbatim, not nulled, so republishing this record
    // reproduces the same wire hash under the same `updatedAt` (I1).
    return (
      entity: program,
      report: SyncReport(
        code: SyncReportCode.unresolvedReference,
        kind: kind,
        recordId: record.address.recordId,
        message: 'Program venue reference is missing locally.',
      ),
    );
  }

  @override
  Future<void> rebuildDerivedIndexes() async {
    await repositories.dances.rebuildAllDerived();
  }

  Future<String?> _missingDanceReference(
    Dance dance, {
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
    required bool allowTombstonedReferences,
  }) async {
    final difficultyId = dance.difficultyLevelId;
    if (difficultyId != null) {
      final difficultyAddress = (
        kind: SyncRecordKind.difficultyLevel,
        recordId: difficultyId,
      );
      final difficulty = inboundLiveAddresses.contains(difficultyAddress)
          ? difficultyId
          : inboundAddresses.contains(difficultyAddress)
          ? null
          : (await (_db.select(_db.difficultyLevels)..where(
                      (row) =>
                          row.id.equals(difficultyId) &
                          (allowTombstonedReferences
                              ? const Constant(true)
                              : row.deletedAt.isNull()),
                    ))
                    .getSingleOrNull())
                ?.id;
      if (difficulty == null) {
        return 'Dance "${dance.id}" references unavailable difficulty '
            '"$difficultyId".';
      }
    }

    final authorIds = dance.authorIds.toSet();
    final authorLookupIds = _referenceIdsToLookUp(
      ids: authorIds,
      kind: SyncRecordKind.choreographer,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (authorLookupIds.isNotEmpty) {
      final rows = await _queryInChunks(
        authorLookupIds,
        (chunk) =>
            (_db.select(_db.choreographers)..where(
                  (row) =>
                      row.id.isIn(chunk) &
                      (allowTombstonedReferences
                          ? const Constant(true)
                          : row.deletedAt.isNull()),
                ))
                .get(),
      );
      final missing = _missingReferenceIds(
        ids: authorIds,
        kind: SyncRecordKind.choreographer,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable choreographer '
            '"${missing.first}".';
      }
    } else if (authorIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: authorIds,
        kind: SyncRecordKind.choreographer,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable choreographer '
            '"${missing.first}".';
      }
    }

    final tagIds = dance.tagIds.toSet();
    final tagLookupIds = _referenceIdsToLookUp(
      ids: tagIds,
      kind: SyncRecordKind.tag,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (tagLookupIds.isNotEmpty) {
      final rows = await _queryInChunks(
        tagLookupIds,
        (chunk) =>
            (_db.select(_db.tags)..where(
                  (row) =>
                      row.id.isIn(chunk) &
                      (allowTombstonedReferences
                          ? const Constant(true)
                          : row.deletedAt.isNull()),
                ))
                .get(),
      );
      final missing = _missingReferenceIds(
        ids: tagIds,
        kind: SyncRecordKind.tag,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable tag '
            '"${missing.first}".';
      }
    } else if (tagIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: tagIds,
        kind: SyncRecordKind.tag,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable tag '
            '"${missing.first}".';
      }
    }

    final sourceIds = dance.sourceCitations
        .map((citation) => citation.sourceId)
        .toSet();
    final sourceLookupIds = _referenceIdsToLookUp(
      ids: sourceIds,
      kind: SyncRecordKind.publishedSource,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (sourceLookupIds.isNotEmpty) {
      final rows = await _queryInChunks(
        sourceLookupIds,
        (chunk) =>
            (_db.select(_db.publishedSources)..where(
                  (row) =>
                      row.id.isIn(chunk) &
                      (allowTombstonedReferences
                          ? const Constant(true)
                          : row.deletedAt.isNull()),
                ))
                .get(),
      );
      final missing = _missingReferenceIds(
        ids: sourceIds,
        kind: SyncRecordKind.publishedSource,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable source '
            '"${missing.first}".';
      }
    } else if (sourceIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: sourceIds,
        kind: SyncRecordKind.publishedSource,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable source '
            '"${missing.first}".';
      }
    }

    final customFieldIds = dance.customFields
        .map((value) => value.fieldId)
        .toSet();
    final customFieldLookupIds = _referenceIdsToLookUp(
      ids: customFieldIds,
      kind: SyncRecordKind.customFieldDef,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (customFieldLookupIds.isNotEmpty) {
      final rows = await _queryInChunks(
        customFieldLookupIds,
        (chunk) =>
            (_db.select(_db.customFieldDefs)..where(
                  (row) =>
                      row.id.isIn(chunk) &
                      (allowTombstonedReferences
                          ? const Constant(true)
                          : row.deletedAt.isNull()),
                ))
                .get(),
      );
      final missing = _missingReferenceIds(
        ids: customFieldIds,
        kind: SyncRecordKind.customFieldDef,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable custom field '
            '"${missing.first}".';
      }
    } else if (customFieldIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: customFieldIds,
        kind: SyncRecordKind.customFieldDef,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable custom field '
            '"${missing.first}".';
      }
    }
    final customFieldIssue = await _invalidCustomFieldValue(
      dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
      inboundRecords: inboundRecords,
    );
    if (customFieldIssue != null) return customFieldIssue;

    final targetDanceIds = dance.links
        .map((link) => link.targetDanceId)
        .whereType<String>()
        .toSet();
    final targetDanceLookupIds = _referenceIdsToLookUp(
      ids: targetDanceIds,
      kind: SyncRecordKind.dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (targetDanceLookupIds.isNotEmpty) {
      final rows = await _queryInChunks(
        targetDanceLookupIds,
        (chunk) =>
            (_db.select(_db.dances)..where(
                  (row) =>
                      row.id.isIn(chunk) &
                      (allowTombstonedReferences
                          ? const Constant(true)
                          : row.deletedAt.isNull()),
                ))
                .get(),
      );
      final missing = _missingReferenceIds(
        ids: targetDanceIds,
        kind: SyncRecordKind.dance,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable related dance '
            '"${missing.first}".';
      }
    } else if (targetDanceIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: targetDanceIds,
        kind: SyncRecordKind.dance,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable related dance '
            '"${missing.first}".';
      }
    }
    return null;
  }

  Future<String?> _missingProgramReference(
    Program program, {
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required bool allowTombstonedReferences,
  }) async {
    final danceIds = program.slots
        .map((slot) => slot.danceId)
        .whereType<String>()
        .toSet();
    final lookupIds = _referenceIdsToLookUp(
      ids: danceIds,
      kind: SyncRecordKind.dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    final rows = await _queryInChunks(
      lookupIds,
      (chunk) =>
          (_db.select(_db.dances)..where(
                (row) =>
                    row.id.isIn(chunk) &
                    (allowTombstonedReferences
                        ? const Constant(true)
                        : row.deletedAt.isNull()),
              ))
              .get(),
    );
    final missing = _missingReferenceIds(
      ids: danceIds,
      kind: SyncRecordKind.dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
      storedLiveIds: rows.map((row) => row.id).toSet(),
    );
    return missing.isEmpty
        ? null
        : 'Program "${program.id}" references unavailable dance '
              '"${missing.first}".';
  }

  Future<String?> _invalidDanceDependentRows(
    Dance dance, {
    required _InboundDependentIndex dependentIndex,
  }) async {
    final duplicateAuthorId = _firstDuplicate(dance.authorIds);
    if (duplicateAuthorId != null) {
      return 'Dance "${dance.id}" contains duplicate choreographer id '
          '"$duplicateAuthorId".';
    }
    final duplicateTagId = _firstDuplicate(dance.tagIds);
    if (duplicateTagId != null) {
      return 'Dance "${dance.id}" contains duplicate tag id "$duplicateTagId".';
    }
    final duplicateSourceId = _firstDuplicate(
      dance.sourceCitations.map((citation) => citation.sourceId),
    );
    if (duplicateSourceId != null) {
      return 'Dance "${dance.id}" contains duplicate source id '
          '"$duplicateSourceId".';
    }
    final linkIds = dance.links.map((link) => link.id).toList();
    final duplicateId = _firstDuplicate(linkIds);
    if (duplicateId != null) {
      return 'Dance "${dance.id}" contains duplicate link id "$duplicateId".';
    }
    if (linkIds.isEmpty) return null;

    for (final linkId in linkIds) {
      for (final owner
          in dependentIndex.danceLinkOwners[linkId] ??
              const <SyncRecordAddress>[]) {
        if (owner.recordId == dance.id) continue;
        return 'Dance link id "$linkId" is also owned by '
            '"${owner.recordId}".';
      }
    }

    final rows = await _queryInChunks(
      linkIds,
      (chunk) => (_db.select(
        _db.danceLinks,
      )..where((row) => row.id.isIn(chunk))).get(),
    );
    for (final row in rows) {
      if (row.danceId != dance.id) {
        return 'Dance link id "${row.id}" is already owned by '
            '"${row.danceId}".';
      }
    }
    return null;
  }

  Future<String?> _invalidProgramDependentRows(
    Program program, {
    required _InboundDependentIndex dependentIndex,
  }) async {
    final slotIds = program.slots.map((slot) => slot.id).toList();
    final duplicateId = _firstDuplicate(slotIds);
    if (duplicateId != null) {
      return 'Program "${program.id}" contains duplicate slot id "$duplicateId".';
    }
    if (slotIds.isEmpty) return null;

    for (final slotId in slotIds) {
      for (final owner
          in dependentIndex.programSlotOwners[slotId] ??
              const <SyncRecordAddress>[]) {
        if (owner.recordId == program.id) continue;
        return 'Program slot id "$slotId" is also owned by '
            '"${owner.recordId}".';
      }
    }

    final rows = await _queryInChunks(
      slotIds,
      (chunk) => (_db.select(
        _db.programSlots,
      )..where((row) => row.id.isIn(chunk))).get(),
    );
    for (final row in rows) {
      if (row.programId != program.id) {
        return 'Program slot id "${row.id}" is already owned by '
            '"${row.programId}".';
      }
    }
    return null;
  }

  _InboundDependentIndex _dependentIndexFor(
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  ) {
    final cached = _dependentIndexCache[inboundRecords];
    if (cached != null) return cached;

    final index = _InboundDependentIndex();
    for (final entry in inboundRecords.entries) {
      try {
        switch (entry.key.kind) {
          case SyncRecordKind.dance:
            final dance =
                _decodeEntity(
                      SyncRecordKind.dance,
                      _normalizeInboundRecord(entry.value).body,
                    )
                    as Dance;
            for (final link in dance.links) {
              index.danceLinkOwners
                  .putIfAbsent(link.id, () => <SyncRecordAddress>[])
                  .add(entry.key);
            }
          case SyncRecordKind.program:
            final program =
                _decodeEntity(
                      SyncRecordKind.program,
                      _normalizeInboundRecord(entry.value).body,
                    )
                    as Program;
            for (final slot in program.slots) {
              index.programSlotOwners
                  .putIfAbsent(slot.id, () => <SyncRecordAddress>[])
                  .add(entry.key);
            }
          default:
            continue;
        }
      } on Object {
        // The current record's decode result reports malformed input; an
        // invalid peer body cannot own a dependent row for another record.
      }
    }
    _dependentIndexCache[inboundRecords] = index;
    return index;
  }

  String? _firstDuplicate(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) return id;
    }
    return null;
  }

  Future<String?> _invalidCustomFieldClassification(
    SyncApplyRecord record,
    Object entity, {
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    if (record.address.kind == SyncRecordKind.customFieldDef) {
      if (entity is CustomFieldDef && !entity.shareable) {
        return 'Inbound custom-field definition '
            '"${record.address.recordId}" is not shareable.';
      }
      return null;
    }
    if (record.address.kind != SyncRecordKind.dance || entity is! Dance) {
      return null;
    }

    for (final value in entity.customFields) {
      final address = (
        kind: SyncRecordKind.customFieldDef,
        recordId: value.fieldId,
      );
      final inbound = inboundRecords[address];
      if (inbound != null) {
        try {
          final definition =
              _decodeEntity(SyncRecordKind.customFieldDef, inbound.body)
                  as CustomFieldDef;
          if (!definition.shareable) {
            return 'Inbound dance contains a value for non-shareable custom '
                'field "${value.fieldId}".';
          }
        } on Object {
          // The malformed definition receives its own malformed-record report.
        }
      } else if (!inboundAddresses.contains(address)) {
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(value.fieldId))).getSingleOrNull();
        final definition = row == null
            ? null
            : CustomFieldDefRepository.toModel(row);
        if (definition != null && !definition.shareable) {
          return 'Inbound dance contains a value for non-shareable custom '
              'field "${value.fieldId}".';
        }
      }
    }
    return null;
  }

  Future<String?> _invalidCustomFieldValue(
    Dance dance, {
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    for (final value in dance.customFields) {
      final address = (
        kind: SyncRecordKind.customFieldDef,
        recordId: value.fieldId,
      );
      if (inboundAddresses.contains(address) &&
          !inboundLiveAddresses.contains(address)) {
        continue;
      }

      late final CustomFieldDef definition;
      if (inboundLiveAddresses.contains(address)) {
        final inbound = inboundRecords[address];
        if (inbound == null) continue;
        try {
          definition =
              _decodeEntity(SyncRecordKind.customFieldDef, inbound.body)
                  as CustomFieldDef;
        } on Object catch (error) {
          return 'Dance "${dance.id}" references malformed custom field '
              '"${value.fieldId}": $error';
        }
      } else {
        final row =
            await (_db.select(_db.customFieldDefs)..where(
                  (table) =>
                      table.id.equals(value.fieldId) & table.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (row == null) continue;
        final decoded = CustomFieldDefRepository.toModel(row);
        if (decoded == null) {
          return 'Dance "${dance.id}" references corrupt custom field '
              '"${value.fieldId}".';
        }
        definition = decoded;
      }

      try {
        encodeCustomFieldValue(value, definition);
      } on ArgumentError catch (error) {
        return 'Dance "${dance.id}" has an invalid value for custom field '
            '"${value.fieldId}": $error';
      }
    }
    return null;
  }

  Set<String> _referenceIdsToLookUp({
    required Iterable<String> ids,
    required SyncRecordKind kind,
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
  }) => {
    for (final id in ids)
      if (!inboundLiveAddresses.contains((kind: kind, recordId: id)) &&
          !inboundAddresses.contains((kind: kind, recordId: id)))
        id,
  };

  Set<String> _missingReferenceIds({
    required Iterable<String> ids,
    required SyncRecordKind kind,
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Set<String> storedLiveIds,
  }) => {
    for (final id in ids)
      if (!inboundLiveAddresses.contains((kind: kind, recordId: id)) &&
          (inboundAddresses.contains((kind: kind, recordId: id)) ||
              !storedLiveIds.contains(id)))
        id,
  };

  SyncReport _malformedReferenceReport(
    SyncApplyRecord record,
    String message,
  ) => SyncReport(
    code: SyncReportCode.malformedRecord,
    kind: record.address.kind,
    recordId: record.address.recordId,
    message: 'Inbound record could not be decoded: $message.',
  );

  /// The stored body for a dance, or `null` for none.
  ///
  /// **This is an inbound path, not a publish path.** Its only caller is
  /// [read], and [read]'s only callers are in `sync_apply.dart`, which uses it
  /// to fetch the current local body an arriving peer record is overlaid onto.
  /// Publication does not come through here: the coordinator publishes from
  /// `snapshot().local` / `.publication`, whose blobs `snapshot` builds
  /// directly with `syncRecordBlobForEntity`. Earlier comments and the spec
  /// text written alongside them called this one of four publish paths; it is
  /// not, and both were corrected with #1347's reporting half.
  ///
  /// **A dance whose stored transcription could not be decoded still returns
  /// `null` here** (#1347), so the overlay base is empty rather than a body
  /// carrying the transcription as an empty array beside a `figuresRaw`
  /// sibling. Conservative in the same direction as the publish-side withhold.
  ///
  /// It raises no withheld report, because nothing is withheld *from a peer*
  /// here. The record's absence from publication is reported once, by the
  /// paths that actually withhold it.
  Future<Map<String, Object?>?> _readDanceBody(String id) async {
    final dance = await repositories.dances.getById(id, includeDeleted: true);
    if (dance == null) return null;
    if (dance.figuresSource is UnreadableFigures ||
        dance.tunesSource is UnreadableTunes) {
      return null;
    }
    return archiveDanceToJson(dance, const {}, includeOptionalFields: true);
  }

  Future<Map<String, Object?>?> _readProgramBody(String id) async {
    final program = await repositories.programs.getById(
      id,
      includeDeleted: true,
    );
    return program == null
        ? null
        : archiveProgramToJson(program, includeOptionalFields: true);
  }

  Future<Map<String, Object?>?> _readChoreographerBody(String id) async {
    final row = await (_db.select(
      _db.choreographers,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return archiveChoreographerToJson(
      Choreographer(
        id: row.id,
        name: row.name,
        website: row.website,
        notes: row.notes,
        email: row.email,
        location: row.location,
        deceased: row.deceased,
      ),
      includeOptionalFields: true,
    );
  }

  Future<Map<String, Object?>?> _readTagBody(String id) async {
    final row = await (_db.select(
      _db.tags,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : archiveTagToJson(
            Tag(id: row.id, name: row.name, color: row.color),
            includeOptionalFields: true,
          );
  }

  Future<Map<String, Object?>?> _readPublishedSourceBody(String id) async {
    final row = await (_db.select(
      _db.publishedSources,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : archivePublishedSourceToJson(
            PublishedSource(
              id: row.id,
              title: row.title,
              author: row.author,
              year: row.year,
              url: row.url,
              notes: row.notes,
            ),
            includeOptionalFields: true,
          );
  }

  Future<Map<String, Object?>?> _readCustomFieldBody(String id) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final field = row == null ? null : CustomFieldDefRepository.toModel(row);
    return field == null
        ? null
        : archiveCustomFieldDefToJson(
            field,
            includeShareable: true,
            includeOptionalFields: true,
          );
  }

  Future<Map<String, Object?>?> _readDifficultyBody(String id) async {
    final row = await (_db.select(
      _db.difficultyLevels,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : archiveDifficultyLevelToJson(
            DifficultyLevel(
              id: row.id,
              label: row.label,
              position: row.position,
            ),
          );
  }

  Future<Map<String, Object?>?> _readVenueBody(String id) async {
    final row = await (_db.select(
      _db.venues,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return archiveVenueToJson(
      Venue(
        id: row.id,
        name: row.name,
        address1: row.address1,
        address2: row.address2,
        city: row.city,
        stateProv: row.stateProv,
        country: row.country,
        postalCode: row.postalCode,
        plus4: row.plus4,
        website: row.website,
        sponsor: row.sponsor,
        eventName: row.eventName,
        time: row.time,
        genericSchedule: row.genericSchedule,
        price: row.price,
        notes: row.notes,
        contact1Name: row.contact1Name,
        contact1Phone: row.contact1Phone,
        contact1Email: row.contact1Email,
        contact2Name: row.contact2Name,
        contact2Phone: row.contact2Phone,
        contact2Email: row.contact2Email,
        provenance: await _venueProvenance(id),
      ),
      includeOptionalFields: true,
    );
  }

  Object _decodeEntity(SyncRecordKind kind, Map<String, Object?> body) {
    return decodeSyncRecordEntity(kind, body);
  }

  Future<bool> _isLiveVenue(String id) async =>
      (await (_db.select(_db.venues)
            ..where((table) => table.id.equals(id) & table.deletedAt.isNull()))
          .getSingleOrNull()) !=
      null;

  Future<Provenance?> _venueProvenance(String id) async {
    final row = await (_db.select(
      _db.venueProvenance,
    )..where((table) => table.venueId.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : Provenance(
            source: row.source,
            externalId: row.externalId,
            importedAt: row.importedAt,
            permission: row.permission,
            license: row.license,
            sourceVersion: row.sourceVersion,
          );
  }

  Future<void> _restoreTimestamps({
    required SyncRecordKind kind,
    required String id,
    required DateTime updatedAt,
    required DateTime? deletedAt,
    required DateTime existenceAt,
  }) async {
    final currentUpdatedAt = await _currentUpdatedAt(kind, id);
    final effectiveUpdatedAt =
        currentUpdatedAt == null || currentUpdatedAt.isBefore(updatedAt)
        ? updatedAt
        : currentUpdatedAt;
    switch (kind) {
      case SyncRecordKind.dance:
        await (_db.update(_db.dances)..where((row) => row.id.equals(id))).write(
          DancesCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.program:
        await (_db.update(
          _db.programs,
        )..where((row) => row.id.equals(id))).write(
          ProgramsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.choreographer:
        await (_db.update(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).write(
          ChoreographersCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.tag:
        await (_db.update(_db.tags)..where((row) => row.id.equals(id))).write(
          TagsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.publishedSource:
        await (_db.update(
          _db.publishedSources,
        )..where((row) => row.id.equals(id))).write(
          PublishedSourcesCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.customFieldDef:
        await (_db.update(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).write(
          CustomFieldDefsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.difficultyLevel:
        await (_db.update(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).write(
          DifficultyLevelsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.venue:
        await (_db.update(_db.venues)..where((row) => row.id.equals(id))).write(
          VenuesCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.setting:
        await (_db.update(
          _db.settings,
        )..where((row) => row.key.equals(id))).write(
          SettingsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
    }
  }

  Future<DateTime?> _currentUpdatedAt(SyncRecordKind kind, String id) async {
    switch (kind) {
      case SyncRecordKind.dance:
        return (await (_db.select(
          _db.dances,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.program:
        return (await (_db.select(
          _db.programs,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.choreographer:
        return (await (_db.select(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.tag:
        return (await (_db.select(
          _db.tags,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.publishedSource:
        return (await (_db.select(
          _db.publishedSources,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.customFieldDef:
        return (await (_db.select(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.difficultyLevel:
        return (await (_db.select(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.venue:
        return (await (_db.select(
          _db.venues,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.setting:
        return (await (_db.select(
          _db.settings,
        )..where((row) => row.key.equals(id))).getSingleOrNull())?.updatedAt;
    }
  }

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Device-local marker for store addresses this device completed a publication
/// against. The marker stores salted, slow verifiers rather than the raw
/// addresses or a fast unsalted hash, so it cannot be turned back into the
/// address it stands for.
const syncLastUsedFingerprintKey = 'sync_last_used_fingerprint';

/// Per-device upload-budget toggle for imported dances (spec §6.1). Read
/// live on every [CompendiumSyncStorage.snapshot] rather than cached, so a
/// mid-session change takes effect on the very next pass. Mirrors the app's
/// own `kSyncExcludeImportsKey`; kept in sync by convention like
/// [syncLastUsedFingerprintKey] mirrors `kSyncLastUsedFingerprintKey`.
const syncExcludeImportsKey = 'sync_exclude_imports';

const _syncIdentityVerifierAlgorithm = 'pbkdf2-sha256';
const _syncIdentityKdfIterations = 600000;
const _syncIdentitySaltBytes = 16;
const _syncIdentityVerifierBytes = 32;
final _syncIdentityRandom = Random.secure();

/// Test-only count of calls to [_deriveSyncIdentityVerifier].
///
/// The derivation is deliberately slow (600,000 HMAC-SHA256 iterations) so a
/// stolen marker file cannot be brute-forced offline; that cost is only safe
/// to keep on the hot sync path because [CompendiumSyncStorage] derives a
/// given sync identity's verifier at most once per instance (see
/// `_identityVerifierMemo`). This counter lets a test assert that invariant
/// directly instead of only inferring it from wall-clock time. Nothing in
/// this package reads it outside tests.
@visibleForTesting
int syncIdentityVerifierDerivationCount = 0;

final class _StoredSyncIdentityVerifier {
  const _StoredSyncIdentityVerifier({
    required this.salt,
    required this.verifier,
  });

  factory _StoredSyncIdentityVerifier.create(String syncId) {
    final salt = List<int>.generate(
      _syncIdentitySaltBytes,
      (_) => _syncIdentityRandom.nextInt(256),
    );
    return _StoredSyncIdentityVerifier(
      salt: salt,
      verifier: _deriveSyncIdentityVerifier(syncId, salt),
    );
  }

  final List<int> salt;
  final List<int> verifier;

  bool matches(String syncId) =>
      _constantTimeEquals(verifier, _deriveSyncIdentityVerifier(syncId, salt));

  Map<String, Object?> toJson() => {
    'algorithm': _syncIdentityVerifierAlgorithm,
    'iterations': _syncIdentityKdfIterations,
    'salt': _encodeVerifierBytes(salt),
    'verifier': _encodeVerifierBytes(verifier),
  };
}

List<_StoredSyncIdentityVerifier> _decodeUsedIdentityVerifiers(Object? marker) {
  if (marker is! List) return [];
  final decoded = <_StoredSyncIdentityVerifier>[];
  for (final value in marker) {
    if (value is! Map ||
        value['algorithm'] != _syncIdentityVerifierAlgorithm ||
        value['iterations'] != _syncIdentityKdfIterations ||
        value['salt'] is! String ||
        value['verifier'] is! String) {
      continue;
    }
    final salt = _decodeVerifierBytes(
      value['salt'] as String,
      expectedLength: _syncIdentitySaltBytes,
    );
    final verifier = _decodeVerifierBytes(
      value['verifier'] as String,
      expectedLength: _syncIdentityVerifierBytes,
    );
    if (salt == null || verifier == null) continue;
    decoded.add(_StoredSyncIdentityVerifier(salt: salt, verifier: verifier));
  }
  return decoded;
}

Set<String> _decodeLegacyIdentityFingerprints(Object? marker) =>
    switch (marker) {
      String value when value.isNotEmpty => {value},
      List<Object?> values => {
        for (final value in values)
          if (value is String && value.isNotEmpty) value,
      },
      _ => <String>{},
    };

String _legacyIdentityFingerprint(String syncId) =>
    sha256Hex(utf8.encode(normalizeSyncId(syncId)));

List<int> _deriveSyncIdentityVerifier(String syncId, List<int> salt) {
  syncIdentityVerifierDerivationCount++;
  final hmac = Hmac(sha256, utf8.encode(normalizeSyncId(syncId)));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final derived = List<int>.from(block);
  for (var iteration = 1; iteration < _syncIdentityKdfIterations; iteration++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < derived.length; index++) {
      derived[index] ^= block[index];
    }
  }
  return derived;
}

String _encodeVerifierBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int>? _decodeVerifierBytes(String value, {required int expectedLength}) {
  if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    return null;
  }
  try {
    final padding = (4 - value.length % 4) % 4;
    final decoded = base64Url.decode('$value${'=' * padding}');
    return decoded.length == expectedLength ? decoded : null;
  } on FormatException {
    return null;
  }
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = min(left.length, right.length);
  for (var index = 0; index < length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
