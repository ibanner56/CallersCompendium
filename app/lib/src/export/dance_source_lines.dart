import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';

/// One display line per published-source citation on [dance], for the dance
/// card's Sources block (OUT-6): `Title — Author, Year (p. 12, no. 3)`.
///
/// The text mirrors the dance-detail source row, minus the URL: a printed card
/// has no use for a link the reader cannot tap. A citation whose shared source
/// has been purged (`sourceFor` returns `null`) still prints its page and
/// number under the localized "(unknown source)" title, as the detail screen
/// does, so the reference is not silently dropped from a handout.
///
/// Only the title, author, year, page and number leave the app — the same
/// fields the dance-detail screen shows. The source's URL and notes are never
/// read.
List<String> danceSourceLines(
  AppLocalizations l10n,
  Dance dance,
  PublishedSource? Function(String sourceId) sourceFor,
) => [
  for (final citation in dance.sourceCitations)
    _line(l10n, citation, sourceFor(citation.sourceId)),
];

String _line(
  AppLocalizations l10n,
  SourceCitation citation,
  PublishedSource? source,
) {
  final title = source?.title ?? l10n.danceSourceUnknown;
  final bib = [
    ?source?.author,
    if (source?.year case final year?) year.toString(),
  ].join(', ');
  final loc = [
    if (citation.page case final page?) l10n.danceSourcePage(page),
    if (citation.number case final number?) l10n.danceSourceNumber(number),
  ].join(', ');
  final head = bib.isEmpty ? title : '$title — $bib';
  return loc.isEmpty ? head : '$head ($loc)';
}
