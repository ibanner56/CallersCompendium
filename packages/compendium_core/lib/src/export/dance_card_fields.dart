/// Pure field-gating logic for a dance card (issue #1434): which of the
/// share-fields picker's [DanceShareField] values turn each line on or off.
///
/// `DanceCardContent.build` is the single caller of these helpers; the text
/// card (`danceToPlainText`) and the PDF builders consume its result, so they
/// can't drift on which fields a selection emits. Figures are handled
/// separately (unaffected by this parameter).
library;

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/phrase_structure.dart';
import '../model/tunes_source.dart';
import 'dance_share_fields.dart';
import 'export_labels.dart';

/// The formation/level/mixer/status/phrase lines, gated by [fields] and in
/// the same order `danceToPlainText` emits them. Each caller wraps the
/// result in its own `pw.Text` widgets.
List<String> danceCardMetaLines(
  Dance dance, {
  required String formationLabel,
  String? levelLabel,
  required String statusLabel,
  required DanceExportLabels labels,
  required Set<DanceShareField> fields,
}) => [
  if (fields.contains(DanceShareField.formation) && _has(formationLabel))
    '${labels.formation}: ${formationLabel.trim()}',
  if (fields.contains(DanceShareField.level) && _has(levelLabel))
    '${labels.level}: ${levelLabel!.trim()}',
  if (fields.contains(DanceShareField.mixer) &&
      dance.mixer &&
      _has(labels.mixer))
    labels.mixer.trim(),
  // Mirrors the on-screen card / text export: only a non-active dance shows
  // a Status line.
  if (fields.contains(DanceShareField.status) &&
      dance.status != DanceStatus.active &&
      _has(statusLabel))
    '${labels.status}: ${statusLabel.trim()}',
  if (fields.contains(DanceShareField.phraseStructure) &&
      _has(dance.phraseStructure.raw))
    '${labels.phrase}: ${phraseStructureText(dance.phraseStructure, labels)}',
];

/// How a card prints [structure]. Named phrases (an English dance's A, B and
/// C, ADR-006 §9.2 point 8) read the way English callers write them: the
/// phrases in playing order, then each one's bars, so `A:2*4*2 + B:1*8*2`
/// prints `AAB (A 4 bars, B 8 bars)`. Bars use [DanceExportLabels.bars], as
/// a figure's count does, and the punctuation is the locale's
/// ([DanceExportLabels.namedPhrases], [DanceExportLabels.namedPhraseSeparator]),
/// so Japanese prints `AAB（A 4小節、B 8小節）`. Any other structure prints as
/// stored, trimmed:
/// making the contra notation readable is issue #2304.
String phraseStructureText(
  PhraseStructure structure,
  DanceExportLabels labels,
) {
  final named = structure.namedPhrases;
  if (named == null) return structure.raw.trim();
  final order = named.map((p) => p.name * p.plays).join();
  final bars = named
      .map((p) => '${p.name} ${labels.bars('${p.bars}', p.bars * 2)}')
      .join(labels.namedPhraseSeparator);
  return labels.namedPhrases(order, bars);
}

/// Resolved, non-blank author names for the dance card, gated on
/// [DanceShareField.authors]. Returns the empty list when the field isn't
/// selected or every provided name is blank/empty.
List<String> danceCardAuthorNames(
  List<String> authorNames,
  Set<DanceShareField> fields,
) {
  if (!fields.contains(DanceShareField.authors)) return const [];
  return authorNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
}

/// Resolved, non-blank tune names for the dance card, gated on
/// [DanceShareField.tunes]. Unreadable stored tunes
/// render as absent, same as an unreadable figures
/// list.
List<String> danceCardTuneNames(Dance dance, Set<DanceShareField> fields) {
  if (!fields.contains(DanceShareField.tunes)) return const [];
  final tuneList = switch (dance.tunesSource) {
    DecodedTunes(:final tunes) => tunes,
    UnreadableTunes() => const <String>[],
  };
  return tuneList.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

/// Resolved, non-blank source-citation lines for the dance card, gated on
/// [DanceShareField.sources]. The caller resolves each citation (title,
/// author/year, page, number) to one display line, as it does for author names.
List<String> danceCardSourceLines(
  List<String> sourceLines,
  Set<DanceShareField> fields,
) {
  if (!fields.contains(DanceShareField.sources)) return const [];
  return sourceLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;
