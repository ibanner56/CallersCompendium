import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'online_title_lookup.dart' show isConnectionFailure;
import 'plaintext_program_import.dart';
import 'program_import_rollback.dart';

/// Hard cap on how many of one program line's [ParsedProgramLine.onlineCandidates]
/// are ever previewed (issue #943).
///
/// Every candidate costs one per-dance fetch (`OnlineSearchService.loadPreview`),
/// which is more than the "one JSON fetch per **confident** import" the
/// import-fidelity rule in `program_import_online_resolver.dart` budgets for —
/// that rule covers the confident-match path; an ambiguous line reviewed by the
/// user is a deliberately different, costlier path, and this cap is its bound.
/// 6 is generous for what "ambiguous" means in practice (a handful of
/// same-titled dances across two sources) while keeping one pasted program's
/// worst case bounded rather than unlimited. Candidates beyond the cap are
/// simply never fetched; the line still shows however many previewed
/// successfully.
const int kMaxAmbiguousCandidatesPerLine = 6;

/// One source-neutral group of candidate rows for the import review screen.
///
/// The group identity is used only for review headings and the one-commit
/// backstop. Program-specific line mapping lives on [AmbiguousReviewImport] so
/// title-list groups never acquire program-slot behavior.
class AmbiguousReviewGroup {
  const AmbiguousReviewGroup({
    required this.id,
    required this.label,
    required this.candidates,
  });

  final String id;
  final String label;
  final List<ImportRecordPlan> candidates;
}

/// A pre-previewed set of ambiguous candidates for import review.
class AmbiguousReviewImport {
  const AmbiguousReviewImport({
    required this.groups,
    this.programLineIndexByGroup = const {},
  });

  final List<AmbiguousReviewGroup> groups;

  /// Generic group id → original program line index. Empty for title-list
  /// groups; only these entries may produce [onProgramCommitted] results.
  final Map<String, int> programLineIndexByGroup;
}

/// One program line no online source could resolve confidently, together with
/// a non-committing preview [ImportRecordPlan] for each candidate that
/// previewed successfully (issue #943). Handed to `ImportReviewScreen` (via
/// `ProgramAmbiguousImport`) so the user adjudicates through the same
/// review/consent step as every other import, mirroring #823's batch-review
/// ruling rather than a new per-line picker.
class ProgramAmbiguousLine {
  const ProgramAmbiguousLine({
    required this.originalLineIndex,
    required this.lineText,
    required this.candidates,
  });

  /// This line's index in the full resolved-lines list the program screen
  /// holds, so a committed candidate can be linked back into the right slot.
  final int originalLineIndex;

  /// The original pasted line, for the review heading.
  final String lineText;

  /// One non-committing preview per candidate that previewed successfully, in
  /// the order [ParsedProgramLine.onlineCandidates] listed them (source order,
  /// then within-source order). The user picks at most one to import, or
  /// leaves them all skipped (keeping the line a note) — enforced at commit
  /// time in `ImportReviewScreen`, not here: every candidate is an ordinary
  /// review row with the normal create/link/duplicate/variation/skip choices.
  final List<ImportRecordPlan> candidates;
}

/// A batch of [ProgramAmbiguousLine]s ready to seed `ImportReviewScreen` with,
/// skipping its manual input phase entirely (mirrors `SharedBundleImport`'s
/// seeding).
class ProgramAmbiguousImport {
  const ProgramAmbiguousImport({required this.lines});

  final List<ProgramAmbiguousLine> lines;

  AmbiguousReviewImport get reviewImport => AmbiguousReviewImport(
    groups: [
      for (final line in lines)
        AmbiguousReviewGroup(
          id: 'program:${line.originalLineIndex}',
          label: line.lineText,
          candidates: line.candidates,
        ),
    ],
    programLineIndexByGroup: {
      for (final line in lines)
        'program:${line.originalLineIndex}': line.originalLineIndex,
    },
  );
}

/// Previews every online candidate of [line]'s ambiguity (issue #943) into a
/// non-committing [ImportRecordPlan], using each candidate's OWN originating
/// source ([OnlineSearchResultRow.source]) via [servicesBySource] — a
/// ContraDB candidate must be previewed against ContraDB, not whichever
/// service happened to resolve first, or the wrong body/id is fetched.
///
/// Capped at [kMaxAmbiguousCandidatesPerLine]; a per-candidate preview failure
/// (fetch/parse [Exception]) drops that one candidate rather than aborting the
/// line, mirroring the per-title error isolation used everywhere else in this
/// batch. A candidate whose source has no entry in [servicesBySource] is
/// dropped the same way (defensive; should not happen — every source that can
/// produce a candidate row is one this function was called with).
Future<List<ImportRecordPlan>> previewAmbiguousCandidates(
  List<OnlineSearchResultRow> candidates, {
  required Map<OnlineSource, OnlineSearchService> servicesBySource,
  required CompendiumRepositories repos,
  DedupeIndex? index,
  DateTime? now,
}) async {
  final plans = <ImportRecordPlan>[];
  for (final row in candidates.take(kMaxAmbiguousCandidatesPerLine)) {
    final service = servicesBySource[row.source];
    if (service == null) continue;
    try {
      final preview = await service.loadPreview(
        repos,
        row,
        now: now,
        index: index,
      );
      plans.add(preview.plan);
    } on Exception {
      // diagnostics: silent — preview failure for one candidate; skip it and continue with remaining candidates
      continue;
    }
  }
  return plans;
}

/// Builds the [ProgramAmbiguousImport] seed for `ImportReviewScreen` from
/// [lines] — the output of [resolveUnmatchedOnline] — previewing every
/// ambiguous line's candidates non-committingly. Returns `null` when no line
/// carries any candidates (nothing to review) or every candidate across every
/// ambiguous line failed to preview, so the caller can skip the review step
/// entirely and leave those lines as notes.
///
/// [servicesBySource] must map every [OnlineSource] any candidate could carry
/// — in practice, every source [resolveUnmatchedOnline] was given (the primary
/// [service] plus its `fallbacks`) — to the same service instance used to
/// resolve it, since [OnlineSearchService.loadPreview] and its dedupe planning
/// are source-specific.
///
/// Like the lookup before it, this stops rather than degrading: a candidate
/// preview that cannot reach its source throws [ProgramImportConnectionFailed]
/// (so the screen says "couldn't reach", not "no matches"), and [isCancelled]
/// is checked before each line, throwing [ProgramImportCancelled].
Future<ProgramAmbiguousImport?> buildProgramAmbiguousImport(
  List<ParsedProgramLine> lines, {
  required Map<OnlineSource, OnlineSearchService> servicesBySource,
  required CompendiumRepositories repos,
  DateTime? now,
  bool Function()? isCancelled,
}) async {
  final watched = {
    for (final MapEntry(:key, :value) in servicesBySource.entries)
      key: ConnectionWatchingService(value),
  };
  final groups = <ProgramAmbiguousLine>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.onlineCandidates.isEmpty) continue;
    if (isCancelled?.call() ?? false) throw const ProgramImportCancelled();
    final plans = await previewAmbiguousCandidates(
      line.onlineCandidates,
      servicesBySource: watched,
      repos: repos,
      now: now,
    );
    if (watched.values.any((s) => s.connectionFailure != null)) {
      throw const ProgramImportConnectionFailed();
    }
    if (plans.isEmpty) continue;
    groups.add(
      ProgramAmbiguousLine(
        originalLineIndex: i,
        lineText: line.text,
        candidates: plans,
      ),
    );
  }
  return groups.isEmpty ? null : ProgramAmbiguousImport(lines: groups);
}

/// Wraps [_inner] for ambiguous-candidate previews: remembers the first
/// connection-class failure ([isConnectionFailure]) from `loadPreview`, and
/// from then on rethrows it without calling [_inner], so
/// [previewAmbiguousCandidates], which swallows per-candidate failures, cannot
/// keep requesting — and its caller can tell "offline" from "nothing
/// previewed". Used by both title-list imports.
class ConnectionWatchingService implements OnlineSearchService {
  ConnectionWatchingService(this._inner);

  final OnlineSearchService _inner;

  /// The first connection-class failure seen, or null.
  Object? connectionFailure;

  @override
  OnlineSource get source => _inner.source;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) =>
      _inner.search(query);

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    final failure = connectionFailure;
    if (failure != null) throw failure;
    try {
      return await _inner.loadPreview(repos, result, now: now, index: index);
    } on Exception catch (e) {
      // diagnostics: silent — recorded and rethrown; the caller reports it as a connection failure
      if (isConnectionFailure(e)) connectionFailure = e;
      rethrow;
    }
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
    List<String> defaultTagIds = const [],
  }) => _inner.import(
    repos,
    plan,
    now: now,
    ambiguousResolution: ambiguousResolution,
    defaultTagIds: defaultTagIds,
  );
}
