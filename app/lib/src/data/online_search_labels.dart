import '../../l10n/app_localizations.dart';
import 'online_search.dart';

/// Localized labels for the online-search enums ([OnlineSource]) and the
/// shared online-import result wording.
///
/// [OnlineSource.label] stays an in-code proper noun ("Caller's Box" /
/// "ContraDB") — a source name, not translated — and is passed straight into
/// ICU placeholders. The per-source attribution line and the import-outcome
/// snackbar text ARE user-facing prose, so UI routes through these helpers
/// (mirroring `collection_query_labels.dart`) rather than reading English off
/// the Flutter-free `online_search.dart` data file.
String onlineSourceAttribution(AppLocalizations l10n, OnlineSource source) =>
    switch (source) {
      OnlineSource.callersBox => l10n.onlineAttributionCallersBox,
      OnlineSource.contraDb => l10n.onlineAttributionContraDb,
    };

/// User-facing snackbar message for an online import [result]. Shared by every
/// source so imports are reported identically. The dance [title] is an
/// untrusted external value; it flows through a gen-l10n placeholder and is
/// rendered as plain text by the caller's `Text` widget.
String onlineImportMessage(AppLocalizations l10n, OnlineImportResult result) =>
    result.kind == OnlineImportKind.alreadyInCollection
    ? l10n.onlineImportAlreadyInCollection(result.title)
    : l10n.onlineImportCreated(result.title);
