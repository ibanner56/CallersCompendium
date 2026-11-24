import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../search/facet_labels.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// The program a [CollectionPicker] adds to (history-filters Q3, extended for
/// suggestions, #2343, #2344): its id, its venue, and where in it the chosen
/// dance will go.
///
/// The program builder's pickers pass one: the add-dance pickers with the end
/// of the program, or the place an add before or after a slot lands (#2339),
/// and **Replace…** with the place of the slot being replaced. Suggested ranks
/// for [position], and is offered only when it is set.
@immutable
class PickerProgramContext {
  const PickerProgramContext({
    this.programId,
    this.venueId,
    this.venue,
    this.venueLabel,
    this.position,
  });

  /// The program's id, or null for a program not saved yet (which has no
  /// history to leave out).
  final String? programId;

  /// The linked venue record's id, if any.
  final String? venueId;

  /// The program's typed venue, used for the venue key when no record is
  /// linked.
  final String? venue;

  /// The venue's name as the builder shows it, for reasons ("Not called at
  /// the Grange since …").
  final String? venueLabel;

  /// Where the chosen dance will go: the slots before and after it, and
  /// whether it takes an alternate's place. Null for no position, so no
  /// Suggested.
  final SuggestionPosition? position;

  /// The venue key calling history groups this program by
  /// (history-filters Q1), or null when it has no venue.
  VenueKey? get venueKey {
    if (venueId case final id? when id.isNotEmpty) return VenueKey.record(id);
    final typed = venue;
    if (typed == null || typed.trim().isEmpty) return null;
    return VenueKey.typed(typed);
  }

  @override
  bool operator ==(Object other) =>
      other is PickerProgramContext &&
      other.programId == programId &&
      other.venueId == venueId &&
      other.venue == venue &&
      other.venueLabel == venueLabel &&
      other.position == position;

  @override
  int get hashCode =>
      Object.hash(programId, venueId, venue, venueLabel, position);
}

/// Ranks a [SuggestionRequest]. The picker uses a [SuggestionWorker] of its
/// own unless a test passes one of these.
typedef SuggestionRanker =
    Future<SuggestionRanking> Function(SuggestionRequest request);

/// What a reason's words need from the picker: how to name a move, the
/// venue, and a date.
class SuggestionReasonLabels {
  SuggestionReasonLabels({
    required this.l10n,
    required this.taxonomy,
    required this.dialect,
    required this.matrixConfig,
    required this.userFigures,
    required this.venueLabel,
    required this.formatDate,
    this.danceTitle,
    this.dialectForColumn,
  });

  /// Reads the date format and localizations from [context].
  factory SuggestionReasonLabels.of(
    BuildContext context, {
    required Taxonomy taxonomy,
    required Dialect dialect,
    required MatrixColumnConfig matrixConfig,
    required UserFigureCatalog userFigures,
    required String? venueLabel,
    String? Function(String danceId)? danceTitle,
    Dialect Function(MatrixColumn column)? dialectForColumn,
  }) {
    final l10n = AppLocalizations.of(context);
    final dateFormat = DateFormatScope.of(context);
    final material = MaterialLocalizations.of(context);
    return SuggestionReasonLabels(
      l10n: l10n,
      taxonomy: taxonomy,
      dialect: dialect,
      matrixConfig: matrixConfig,
      userFigures: userFigures,
      // A venue key with no name to show (a linked record not loaded yet, or
      // deleted, and nothing typed) reads as the builder's own hint does.
      venueLabel: venueLabel != null && venueLabel.trim().isNotEmpty
          ? venueLabel
          : l10n.programsVenueLinkedHintFallbackName,
      formatDate: (date) => formatEventDate(date, dateFormat, material, l10n),
      danceTitle: danceTitle,
      dialectForColumn: dialectForColumn,
    );
  }

  final AppLocalizations l10n;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final MatrixColumnConfig matrixConfig;
  final UserFigureCatalog userFigures;
  final String venueLabel;
  final String Function(DateTime date) formatDate;

  /// The title of a program dance a reason names
  /// ([SuggestionReason.neighborDanceId]), or null when it cannot be named;
  /// the reason then says "the previous dance" or "the next dance".
  final String? Function(String danceId)? danceTitle;

  /// The dialect a column is named in, when it is not [dialect]: the one the
  /// program matrix names the same column in, so a reason and the column it
  /// points at read alike (#2294). Null names every column in [dialect].
  final Dialect Function(MatrixColumn column)? dialectForColumn;

  String _move(String key) {
    final column = matrixColumnForKey(
      key,
      taxonomy: taxonomy,
      config: matrixConfig,
      userFigures: userFigures,
    );
    return matrixColumnLabel(
      column,
      taxonomy,
      dialectForColumn?.call(column) ?? dialect,
      config: matrixConfig,
    );
  }

  /// The sentence for [reason].
  String text(SuggestionReason reason) {
    final formation = reason.formation == null
        ? ''
        : formationShapeLabel(l10n, reason.formation!);
    final next = reason.neighbor == SuggestionNeighbor.next;
    // The neighbour by name, and which side it is on (#2344): "…as Chorus
    // Jig, after it" when this dance would follow it.
    final neighborId = reason.neighborDanceId;
    final dance = neighborId == null ? null : danceTitle?.call(neighborId);
    return switch (reason.kind) {
      SuggestionReasonKind.newMoves => l10n.suggestionReasonNewMoves(
        reason.count ?? 1,
      ),
      SuggestionReasonKind.beatOverlap => switch ((next, dance)) {
        (true, final String d) => l10n.suggestionReasonBeatOverlapBeforeDance(
          _move(reason.moveKey!),
          d,
        ),
        (false, final String d) => l10n.suggestionReasonBeatOverlapAfterDance(
          _move(reason.moveKey!),
          d,
        ),
        (true, null) => l10n.suggestionReasonBeatOverlapNext(
          _move(reason.moveKey!),
        ),
        (false, null) => l10n.suggestionReasonBeatOverlapPrevious(
          _move(reason.moveKey!),
        ),
      },
      SuggestionReasonKind.phraseOverlap => switch ((next, dance)) {
        (true, final String d) => l10n.suggestionReasonPhraseOverlapBeforeDance(
          _move(reason.moveKey!),
          d,
        ),
        (false, final String d) => l10n.suggestionReasonPhraseOverlapAfterDance(
          _move(reason.moveKey!),
          d,
        ),
        (true, null) => l10n.suggestionReasonPhraseOverlapNext(
          _move(reason.moveKey!),
        ),
        (false, null) => l10n.suggestionReasonPhraseOverlapPrevious(
          _move(reason.moveKey!),
        ),
      },
      SuggestionReasonKind.alreadyInProgram =>
        l10n.suggestionReasonAlreadyInProgram,
      SuggestionReasonKind.sameFormationAsNeighbor => switch ((next, dance)) {
        (true, final String d) => l10n.suggestionReasonSameFormationBeforeDance(
          formation,
          d,
        ),
        (false, final String d) => l10n.suggestionReasonSameFormationAfterDance(
          formation,
          d,
        ),
        (true, null) => l10n.suggestionReasonSameFormationNext(formation),
        (false, null) => l10n.suggestionReasonSameFormationPrevious(formation),
      },
      SuggestionReasonKind.formationCommonTonight =>
        l10n.suggestionReasonFormationCommon(reason.count ?? 0, formation),
      SuggestionReasonKind.firstFormationTonight =>
        l10n.suggestionReasonFirstFormation(formation),
      SuggestionReasonKind.fitsCurve => l10n.suggestionReasonFitsCurve,
      SuggestionReasonKind.harderThanCurve =>
        l10n.suggestionReasonHarderThanCurve,
      SuggestionReasonKind.easierThanCurve =>
        l10n.suggestionReasonEasierThanCurve,
      SuggestionReasonKind.calledHereRecently =>
        l10n.suggestionReasonCalledHereRecently(
          venueLabel,
          formatDate(reason.date!),
        ),
      SuggestionReasonKind.notCalledHereSince =>
        l10n.suggestionReasonNotCalledHereSince(
          venueLabel,
          formatDate(reason.date!),
        ),
      SuggestionReasonKind.neverCalledHere =>
        l10n.suggestionReasonNeverCalledHere(venueLabel),
      SuggestionReasonKind.venueSkippedNoVenue =>
        l10n.suggestionReasonVenueSkipped,
      SuggestionReasonKind.noFactorApplied => l10n.suggestionReasonNoFactor,
      SuggestionReasonKind.englishNotCovered =>
        l10n.suggestionReasonEnglishNotCovered,
    };
  }

  /// A row's reason line: its headline reasons, joined.
  String line(RankedSuggestion suggestion) =>
      suggestion.headline.map(text).join(' · ');
}

/// The localized name of a suggestion factor.
String suggestionFactorTitle(AppLocalizations l10n, SuggestionFactor factor) =>
    switch (factor) {
      SuggestionFactor.matrixVariety => l10n.suggestionFactorMatrixVarietyTitle,
      SuggestionFactor.formationBalance =>
        l10n.suggestionFactorFormationBalanceTitle,
      SuggestionFactor.difficultyCurve =>
        l10n.suggestionFactorDifficultyCurveTitle,
      SuggestionFactor.venueRecency => l10n.suggestionFactorVenueRecencyTitle,
    };

/// The **Why?** dialog: every reason that moved [suggestion], each marked as
/// raising or lowering it, then its notes (a factor that was skipped).
Future<void> showSuggestionWhyDialog(
  BuildContext context, {
  required String title,
  required RankedSuggestion suggestion,
  required SuggestionReasonLabels labels,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    animationStyle: AppMotion.styleFor(context),
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('suggestion-why-dialog'),
      title: Text(l10n.suggestionWhyTitle(title)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reason in suggestion.reasons)
              _WhyRow(reason: reason, text: labels.text(reason), l10n: l10n),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

class _WhyRow extends StatelessWidget {
  const _WhyRow({required this.reason, required this.text, required this.l10n});

  final SuggestionReason reason;
  final String text;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final factor = reason.factor;
    // Shape, not colour, says which way it moved the dance (ux.md §4).
    final (icon, semantics) = !reason.moved
        ? (Icons.info_outline, text)
        : reason.effect > 0
        ? (Icons.arrow_upward, l10n.suggestionWhyRaises(text))
        : (Icons.arrow_downward, l10n.suggestionWhyLowers(text));
    return Semantics(
      label: factor == null || !reason.moved
          ? semantics
          : '$semantics (${suggestionFactorTitle(l10n, factor)})',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text),
                  if (factor != null && reason.moved)
                    Text(
                      suggestionFactorTitle(l10n, factor),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
