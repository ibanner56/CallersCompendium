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
    '${labels.phrase}: ${dance.phraseStructure.raw.trim()}',
];

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

bool _has(String? value) => value != null && value.trim().isNotEmpty;
