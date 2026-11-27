import '../../l10n/app_localizations.dart';

/// [sentences] as one message, joined the way the UI language joins
/// sentences ([AppLocalizations.commonSentencePair]): with a space in most
/// languages, with nothing in Japanese. Empty when there are none.
String joinSentences(AppLocalizations l10n, Iterable<String> sentences) =>
    sentences.isEmpty ? '' : sentences.reduce(l10n.commonSentencePair);
