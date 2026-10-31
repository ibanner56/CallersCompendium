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
///
/// [OnlineImportKind.needsConfirmation],
/// [OnlineImportKind.needsConfirmationIdentical] and
/// [OnlineImportKind.needsPossibleMatchChoice] must never reach this function
/// — every call site is responsible for intercepting them and showing a
/// resolution dialog before calling this function with the final result. This is
/// enforced by the [StateError]s below; a call site that forgets to intercept
/// will fail loudly rather than silently showing "imported" when nothing was
/// written.
bool _replacedExistingDance(OnlineImportResult result) {
  final id = result.danceId;
  final session = result.session;
  return id != null &&
      session != null &&
      !session.insertedDanceIds.contains(id);
}

String onlineImportMessage(AppLocalizations l10n, OnlineImportResult result) =>
    switch (result.kind) {
      OnlineImportKind.alreadyInCollection =>
        l10n.onlineImportAlreadyInCollection(result.title),
      // "Same dance": the import was written over an existing dance under its
      // own id, so nothing new was imported (B16).
      OnlineImportKind.created when _replacedExistingDance(result) =>
        l10n.onlineImportUpdated(result.title),
      OnlineImportKind.created => l10n.onlineImportCreated(result.title),
      OnlineImportKind.needsConfirmation => throw StateError(
        'onlineImportMessage reached with needsConfirmation for '
        '"${result.title}". The call site must intercept '
        'OnlineImportKind.needsConfirmation and show a resolution dialog '
        'before passing the final result to this function.',
      ),
      OnlineImportKind.needsConfirmationIdentical => throw StateError(
        'onlineImportMessage reached with needsConfirmationIdentical for '
        '"${result.title}". The call site must intercept '
        'OnlineImportKind.needsConfirmationIdentical and show a resolution '
        'dialog before passing the final result to this function.',
      ),
      OnlineImportKind.needsPossibleMatchChoice => throw StateError(
        'onlineImportMessage reached with needsPossibleMatchChoice for '
        '"${result.title}". The call site must intercept '
        'OnlineImportKind.needsPossibleMatchChoice and let the user choose '
        'before passing the final result to this function.',
      ),
    };
