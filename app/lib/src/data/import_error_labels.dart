import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import 'import_io.dart';
import 'title_list_import.dart';

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
    UrlFetchFailureReason.timeout =>
      error.timeoutSeconds == null
          ? l10n.importErrorUnreachable
          : l10n.importErrorTimeout(error.timeoutSeconds!),
    UrlFetchFailureReason.unreachable => l10n.importErrorUnreachable,
    UrlFetchFailureReason.httpStatus =>
      error.statusCode == null
          ? l10n.importErrorUnreachable
          : l10n.importErrorHttpStatus(error.statusCode!),
    UrlFetchFailureReason.emptyResponse => l10n.importErrorEmptyResponse,
    UrlFetchFailureReason.unsupportedSharedLink =>
      l10n.importErrorUnsupportedSharedLink,
    UrlFetchFailureReason.callersBoxEmptyInput =>
      l10n.importErrorCallersBoxEmptyInput,
    UrlFetchFailureReason.callersBoxInvalidUrl =>
      l10n.importErrorCallersBoxInvalidUrl,
    UrlFetchFailureReason.callersBoxMissingId =>
      l10n.importErrorCallersBoxMissingId,
    UrlFetchFailureReason.callersBoxEmptySearch =>
      l10n.importErrorCallersBoxEmptySearch,
    UrlFetchFailureReason.searchTimeout =>
      error.timeoutSeconds == null
          ? l10n.importErrorUnreachable
          : l10n.importErrorSearchTimeout(error.timeoutSeconds!),
    UrlFetchFailureReason.callersBoxUnreachable =>
      l10n.importErrorCallersBoxUnreachable,
    UrlFetchFailureReason.callersBoxHttpStatus =>
      error.statusCode == null
          ? l10n.importErrorCallersBoxUnreachable
          : l10n.importErrorCallersBoxHttpStatus(error.statusCode!),
    UrlFetchFailureReason.callersBoxEmptyPage =>
      l10n.importErrorCallersBoxEmptyPage,
    UrlFetchFailureReason.callersBoxNoImportableDance =>
      l10n.importErrorCallersBoxNoDance,
    UrlFetchFailureReason.callersBoxImportFailed =>
      l10n.importErrorCallersBoxImportFailed,
    UrlFetchFailureReason.callersBoxUnsupportedHost =>
      l10n.importErrorCallersBoxUnsupportedHost,
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
    UrlFetchFailureReason.contraDbUnsupportedHost =>
      l10n.importErrorContraDbUnsupportedHost,
    UrlFetchFailureReason.contraDbUnreachable =>
      l10n.importErrorContraDbUnreachable,
    UrlFetchFailureReason.contraDbHttpStatus =>
      error.statusCode == null
          ? l10n.importErrorContraDbUnreachable
          : l10n.importErrorContraDbHttpStatus(error.statusCode!),
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
      ImportSourceKind.titleList => l10n.importSourceLabelTitleList,
      ImportSourceKind.publishedCollection =>
        l10n.importSourceLabelPublishedCollection,
    };

/// Localized display name for the provenance attached to an imported draft.
String provenanceSourceLabel(AppLocalizations l10n, ProvenanceSource source) =>
    switch (source) {
      ProvenanceSource.callersbox => "The Caller's Box",
      ProvenanceSource.contradb => 'ContraDB',
      ProvenanceSource.callersCompanion => "Caller's Companion",
      ProvenanceSource.manual => l10n.danceProvenanceSourceManual,
      ProvenanceSource.json => l10n.danceProvenanceSourceJson,
      ProvenanceSource.publishedCollection => l10n.publishedCollectionsTitle,
    };

/// Localized refusal for a pasted title list that tripped a hard cap
/// ([TitleListTooLargeException]).
///
/// The paste is refused outright rather than truncated, so the too-many-titles
/// message names the cap and how many titles were actually pasted, letting the
/// user see how far over they are instead of guessing.
///
/// The raw-size refusal deliberately names **no** number: it caps the *length of
/// the pasted text*, not the number of titles, and a paste of very long lines
/// can trip it with far fewer than [kMaxTitleListTitles] titles — so citing that
/// limit would misdescribe why the paste was refused (raised in review of PR
/// #842). Note the cap is in UTF-16 code units, not bytes.
String titleListTooLargeMessage(
  AppLocalizations l10n,
  TitleListTooLargeException error,
) => switch (error.rejection) {
  TitleListRejection.tooManyTitles => l10n.importTitleListTooManyTitles(
    error.count,
    kMaxTitleListTitles,
  ),
  TitleListRejection.textTooLong => l10n.importTitleListTextTooLong,
};

/// Localized explanation of why a pasted title produced nothing importable
/// (issue #823).
///
/// These are kept distinct rather than collapsed into one "not found" because
/// they call for different follow-up: a fetch error is worth retrying, a title
/// the source has never heard of is not, and several exact matches means the
/// source *has* it but cannot say which one was meant. Like every other message
/// here they are generic prose — no URL, no raw server text (CWE-209).
String titleListNotFoundReasonMessage(
  AppLocalizations l10n,
  TitleListNotFoundReason reason,
) => switch (reason) {
  TitleListNotFoundReason.noResults => l10n.importTitleListReasonNoResults,
  TitleListNotFoundReason.noExactMatch =>
    l10n.importTitleListReasonNoExactMatch,
  TitleListNotFoundReason.multipleExactMatches =>
    l10n.importTitleListReasonMultipleExactMatches,
  TitleListNotFoundReason.fetchError => l10n.importTitleListReasonFetchError,
  TitleListNotFoundReason.lineTooLong => l10n.importTitleListReasonLineTooLong,
};
