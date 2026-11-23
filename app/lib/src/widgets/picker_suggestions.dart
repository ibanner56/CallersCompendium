import 'dart:isolate';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../search/facet_labels.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// The program a [CollectionPicker] adds to (history-filters Q3, extended for
/// suggestions, #2343): its id, its venue, and its slots.
///
/// Only the program builder's add-dance pickers pass one. [slots] is set only
/// when the picker adds at the end of the program, the one position Suggested
/// ranks for; while the builder adds before or after a slot (#2339) it is null
/// and Suggested is not offered (#2344).
@immutable
class PickerProgramContext {
  const PickerProgramContext({
    this.programId,
    this.venueId,
    this.venue,
    this.venueLabel,
    this.slots,
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

  /// Every slot of the program, in order, when the picker adds at the end.
  final List<ProgramSlot>? slots;

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
      _slotsEqual(other.slots, slots);

  @override
  int get hashCode => Object.hash(
    programId,
    venueId,
    venue,
    venueLabel,
    slots == null ? null : Object.hashAll(slots!),
  );

  static bool _slotsEqual(List<ProgramSlot>? a, List<ProgramSlot>? b) =>
      a == null ? b == null : b != null && listEquals(a, b);
}

/// Ranks a [SuggestionRequest]: [rankSuggestionsOffUiThread] in the app, a
/// spy in tests.
typedef SuggestionRanker =
    Future<SuggestionRanking> Function(SuggestionRequest request);

/// Ranks on a short-lived background isolate, so ranking the whole collection
/// never holds up a frame.
Future<SuggestionRanking> rankSuggestionsOffUiThread(
  SuggestionRequest request,
) => Isolate.run(() => rankSuggestions(request));

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
  });

  /// Reads the date format and localizations from [context].
  factory SuggestionReasonLabels.of(
    BuildContext context, {
    required Taxonomy taxonomy,
    required Dialect dialect,
    required MatrixColumnConfig matrixConfig,
    required UserFigureCatalog userFigures,
    required String? venueLabel,
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
      venueLabel: venueLabel ?? '',
      formatDate: (date) => formatEventDate(date, dateFormat, material, l10n),
    );
  }

  final AppLocalizations l10n;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final MatrixColumnConfig matrixConfig;
  final UserFigureCatalog userFigures;
  final String venueLabel;
  final String Function(DateTime date) formatDate;

  String _move(String key) => matrixColumnLabel(
    matrixColumnForKey(
      key,
      taxonomy: taxonomy,
      config: matrixConfig,
      userFigures: userFigures,
    ),
    taxonomy,
    dialect,
    config: matrixConfig,
  );

  /// The sentence for [reason].
  String text(SuggestionReason reason) {
    final formation = reason.formation == null
        ? ''
        : formationShapeLabel(l10n, reason.formation!);
    final next = reason.neighbor == SuggestionNeighbor.next;
    return switch (reason.kind) {
      SuggestionReasonKind.newMoves => l10n.suggestionReasonNewMoves(
        reason.count ?? 1,
      ),
      SuggestionReasonKind.beatOverlap =>
        next
            ? l10n.suggestionReasonBeatOverlapNext(_move(reason.moveKey!))
            : l10n.suggestionReasonBeatOverlapPrevious(_move(reason.moveKey!)),
      SuggestionReasonKind.sameFormationAsNeighbor =>
        next
            ? l10n.suggestionReasonSameFormationNext(formation)
            : l10n.suggestionReasonSameFormationPrevious(formation),
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
