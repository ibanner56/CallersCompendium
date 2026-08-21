import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'plaintext_program_import.dart';

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
Future<List<ImportRecordPlan>> _previewAmbiguousCandidates(
  List<OnlineSearchResultRow> candidates, {
  required Map<OnlineSource, OnlineSearchService> servicesBySource,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final plans = <ImportRecordPlan>[];
  for (final row in candidates.take(kMaxAmbiguousCandidatesPerLine)) {
    final service = servicesBySource[row.source];
    if (service == null) continue;
    try {
      final preview = await service.loadPreview(repos, row, now: now);
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
Future<ProgramAmbiguousImport?> buildProgramAmbiguousImport(
  List<ParsedProgramLine> lines, {
  required Map<OnlineSource, OnlineSearchService> servicesBySource,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final groups = <ProgramAmbiguousLine>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.onlineCandidates.isEmpty) continue;
    final plans = await _previewAmbiguousCandidates(
      line.onlineCandidates,
      servicesBySource: servicesBySource,
      repos: repos,
      now: now,
    );
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
