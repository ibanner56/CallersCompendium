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
    '${labels.labelled(labels.formation)}${formationLabel.trim()}',
  if (fields.contains(DanceShareField.level) && _has(levelLabel))
    '${labels.labelled(labels.level)}${levelLabel!.trim()}',
  if (fields.contains(DanceShareField.mixer) &&
      dance.mixer &&
      _has(labels.mixer))
    labels.mixer.trim(),
  // Mirrors the on-screen card / text export: only a non-active dance shows
  // a Status line.
  if (fields.contains(DanceShareField.status) &&
      dance.status != DanceStatus.active &&
      _has(statusLabel))
    '${labels.labelled(labels.status)}${statusLabel.trim()}',
  // A free-form square (ADR-007 §8.1) keeps a phrase structure it does not
  // use, so it prints none.
  if (fields.contains(DanceShareField.phraseStructure) &&
      !dance.isFreeForm &&
      _has(dance.phraseStructure.raw))
    '${labels.labelled(labels.phrase)}${phraseStructureText(dance.phraseStructure, labels)}',
];

/// How a card prints [structure]. Named phrases (an English dance's A, B and
/// C, ADR-006 §9.2 point 8) read the way English callers write them: the
/// phrases in playing order, then each one's bars, so `A:2*4*2 + B:1*8*2`
/// prints `AAB (A 4 bars, B 8 bars)`. Bars use [DanceExportLabels.bars], as
/// a figure's count does, and the punctuation is the locale's
/// ([DanceExportLabels.namedPhrases], [DanceExportLabels.namedPhraseSeparator]),
/// so Japanese prints `AAB（A 4小節、B 8小節）`. Any other structure prints as
/// stored, trimmed, so a contra card keeps The Caller's Box formula as it is;
/// the editor sets that text as rows (#2304) and the card still prints it.
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

/// The credit lines for the dance card, gated on [DanceShareField.authors]:
/// the authors with the year the dance was composed (`Pat Shaw (1951)`), then
/// the interpreters with the year of the interpretation
/// (`Interpreted by Cecil Sharp (1916)`). Each line leaves out the names or
/// the year when either is missing and is itself left out with neither, as on
/// the dance detail screen. Blank names are dropped.
List<String> danceCardCreditLines(
  Dance dance, {
  required List<String> authorNames,
  required List<String> interpreterNames,
  required DanceExportLabels labels,
  required Set<DanceShareField> fields,
}) {
  if (!fields.contains(DanceShareField.authors)) return const [];
  String names(List<String> raw) =>
      raw.map((n) => n.trim()).where((n) => n.isNotEmpty).join(', ');
  final authors = names(authorNames);
  final composed = dance.composedOn?.year.toString();
  final interpreters = names(interpreterNames);
  final interpreted = dance.interpretedOn?.year.toString();
  return [
    ?switch ((authors.isEmpty, composed)) {
      (true, null) => null,
      (false, null) => authors,
      (true, final year?) => labels.composedYear(year),
      (false, final year?) => labels.authorsWithYear(authors, year),
    },
    ?switch ((interpreters.isEmpty, interpreted)) {
      (true, null) => null,
      (false, null) => labels.interpretedBy(interpreters),
      (true, final year?) => labels.interpretedYear(year),
      (false, final year?) => labels.interpretedByWithYear(interpreters, year),
    },
  ];
}

/// The tune-detail lines for the dance card, gated on
/// [DanceShareField.music]: the meter and key on one line
/// (`Meter: 6/8 · Key: G minor`, either part left out when blank), then the
/// Barnes reference (`Barnes: BIII p. 92`). [render] is applied to the typed
/// meter and key, not to the labels, so the caller can pass the card's
/// discouraged-term rendering. The Barnes reference is printed as typed, as
/// the title is: it names a book and often a tune, whose name that rendering
/// would reword (the maintainer, decision sheet question 18).
List<String> danceCardMusicLines(
  Dance dance, {
  required DanceExportLabels labels,
  required Set<DanceShareField> fields,
  required String Function(String value) render,
}) {
  if (!fields.contains(DanceShareField.music)) return const [];
  final meter = dance.meter.trim();
  final key = dance.musicalKey.trim();
  final barnes = dance.barnesReference.trim();
  final meterAndKey = [
    if (meter.isNotEmpty) labels.meter(render(meter)),
    if (key.isNotEmpty) labels.musicalKey(render(key)),
  ];
  return [
    if (meterAndKey.isNotEmpty) meterAndKey.join(' · '),
    if (barnes.isNotEmpty) labels.barnes(barnes),
  ];
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
