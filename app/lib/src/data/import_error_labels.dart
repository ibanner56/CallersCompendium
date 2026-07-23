import '../../l10n/app_localizations.dart';
import 'import_io.dart';

/// Localized presentation of the typed import/fetch errors and import-source
/// labels raised by the Flutter-free data layer (`import_io.dart`,
/// `callersbox_online.dart`, `contradb_online.dart`).
///
/// The data layer never bakes English prose into its exceptions; it throws a
/// [UrlFetchFailureReason] discriminator (plus typed fields such as
/// [UrlFetchException.statusCode] / [UrlFetchException.timeoutSeconds]) or an
/// [ImportFileTooLargeException], and identifies an [ImportSource] by its
/// [ImportSourceKind]. This mapper — living beside the other data helpers but
/// importing [AppLocalizations] like `online_search_labels.dart` — turns those
/// into localized strings at the presentation boundary.
///
/// Security: the returned strings are generic, user-safe prose. They never
/// contain a URL, file path, or raw lower-layer/server error text (CWE-209).
/// The only dynamic values are the typed [int] status/second counts, which flow
/// through gen-l10n placeholders and are rendered as plain text by the caller.
String importErrorMessage(AppLocalizations l10n, UrlFetchException error) {
  return switch (error.reason) {
    UrlFetchFailureReason.emptyUrl => l10n.importErrorEmptyUrl,
    UrlFetchFailureReason.invalidUrl => l10n.importErrorInvalidUrl,
    UrlFetchFailureReason.insecureScheme => l10n.importErrorInsecureScheme,
    UrlFetchFailureReason.blockedHost => l10n.importErrorBlockedHost,
    UrlFetchFailureReason.tooManyRedirects => l10n.importErrorTooManyRedirects,
    UrlFetchFailureReason.responseTooLarge => l10n.importErrorResponseTooLarge,
    UrlFetchFailureReason.timeout => l10n.importErrorTimeout(
      error.timeoutSeconds ?? 0,
    ),
    UrlFetchFailureReason.unreachable => l10n.importErrorUnreachable,
    UrlFetchFailureReason.httpStatus => l10n.importErrorHttpStatus(
      error.statusCode ?? 0,
    ),
    UrlFetchFailureReason.emptyResponse => l10n.importErrorEmptyResponse,
    UrlFetchFailureReason.callersBoxEmptyInput =>
      l10n.importErrorCallersBoxEmptyInput,
    UrlFetchFailureReason.callersBoxInvalidUrl =>
      l10n.importErrorCallersBoxInvalidUrl,
    UrlFetchFailureReason.callersBoxMissingId =>
      l10n.importErrorCallersBoxMissingId,
    UrlFetchFailureReason.callersBoxEmptySearch =>
      l10n.importErrorCallersBoxEmptySearch,
    UrlFetchFailureReason.searchTimeout => l10n.importErrorSearchTimeout(
      error.timeoutSeconds ?? 0,
    ),
    UrlFetchFailureReason.callersBoxUnreachable =>
      l10n.importErrorCallersBoxUnreachable,
    UrlFetchFailureReason.callersBoxHttpStatus =>
      l10n.importErrorCallersBoxHttpStatus(error.statusCode ?? 0),
    UrlFetchFailureReason.callersBoxEmptyPage =>
      l10n.importErrorCallersBoxEmptyPage,
    UrlFetchFailureReason.callersBoxNoImportableDance =>
      l10n.importErrorCallersBoxNoDance,
    UrlFetchFailureReason.callersBoxImportFailed =>
      l10n.importErrorCallersBoxImportFailed,
    UrlFetchFailureReason.contraDbEmptyTitle =>
      l10n.importErrorContraDbEmptyTitle,
    UrlFetchFailureReason.contraDbEmptyDanceInput =>
      l10n.importErrorContraDbEmptyDanceInput,
    UrlFetchFailureReason.contraDbInvalidDanceUrl =>
      l10n.importErrorContraDbInvalidDanceUrl,
    UrlFetchFailureReason.contraDbMissingDanceId =>
      l10n.importErrorContraDbMissingDanceId,
    UrlFetchFailureReason.contraDbEmptyProgramInput =>
      l10n.importErrorContraDbEmptyProgramInput,
    UrlFetchFailureReason.contraDbInvalidProgramUrl =>
      l10n.importErrorContraDbInvalidProgramUrl,
    UrlFetchFailureReason.contraDbMissingProgramId =>
      l10n.importErrorContraDbMissingProgramId,
    UrlFetchFailureReason.contraDbInvalidProgramLink =>
      l10n.importErrorContraDbInvalidProgramLink,
    UrlFetchFailureReason.contraDbUnreachable =>
      l10n.importErrorContraDbUnreachable,
    UrlFetchFailureReason.contraDbHttpStatus =>
      l10n.importErrorContraDbHttpStatus(error.statusCode ?? 0),
    UrlFetchFailureReason.contraDbEmptyResponse =>
      l10n.importErrorContraDbEmptyResponse,
    UrlFetchFailureReason.contraDbNoImportableDance =>
      l10n.importErrorContraDbNoDance,
    UrlFetchFailureReason.contraDbImportFailed =>
      l10n.importErrorContraDbImportFailed,
  };
}

/// Localized message for an [ImportFileTooLargeException]. The exception's
/// [ImportFileTooLargeException.length] is intentionally not shown to the user.
String importFileTooLargeMessage(
  AppLocalizations l10n,
  ImportFileTooLargeException error,
) => l10n.importErrorFileTooLarge;

/// Localized display name for an import [kind], shown in the import-source
/// dropdown and the "Import from {source}." headings.
String importSourceLabel(AppLocalizations l10n, ImportSourceKind kind) =>
    switch (kind) {
      ImportSourceKind.genericJson => l10n.importSourceLabelGenericJson,
      ImportSourceKind.callersBox => l10n.importSourceLabelCallersBox,
      ImportSourceKind.contraDb => l10n.importSourceLabelContraDb,
      ImportSourceKind.callersCompanionUsr =>
        l10n.importSourceLabelCallersCompanionUsr,
    };
