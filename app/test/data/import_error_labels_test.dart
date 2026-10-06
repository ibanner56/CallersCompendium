import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/import_error_labels.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reasons that carry a dynamic [int] (status code or timeout seconds).
const _statusReasons = {
  UrlFetchFailureReason.httpStatus,
  UrlFetchFailureReason.callersBoxHttpStatus,
  UrlFetchFailureReason.contraDbHttpStatus,
};
const _timeoutReasons = {
  UrlFetchFailureReason.timeout,
  UrlFetchFailureReason.searchTimeout,
  UrlFetchFailureReason.callersBoxTimeout,
  UrlFetchFailureReason.contraDbTimeout,
};

/// The opaque failures that wrap a lower-layer/server message we must never
/// surface to the user (CWE-209). They map to a fixed, generic string.
const _opaqueReasons = {
  UrlFetchFailureReason.callersBoxNoImportableDance,
  UrlFetchFailureReason.callersBoxImportFailed,
  UrlFetchFailureReason.contraDbNoImportableDance,
  UrlFetchFailureReason.contraDbImportFailed,
};

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  UrlFetchException build(UrlFetchFailureReason reason) {
    if (_statusReasons.contains(reason)) {
      return UrlFetchException(reason, statusCode: 503);
    }
    if (_timeoutReasons.contains(reason)) {
      return UrlFetchException(reason, timeoutSeconds: 30);
    }
    return UrlFetchException(reason);
  }

  group('importErrorMessage', () {
    test('maps every reason to a non-empty localized string', () {
      for (final reason in UrlFetchFailureReason.values) {
        final message = importErrorMessage(l10n, build(reason));
        expect(message, isNotEmpty, reason: 'no message for $reason');
      }
    });

    test('each status reason renders exactly its localized getter', () {
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.httpStatus,
            statusCode: 418,
          ),
        ),
        l10n.importErrorHttpStatus(418),
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.callersBoxHttpStatus,
            statusCode: 418,
          ),
        ),
        l10n.importErrorCallersBoxHttpStatus(418),
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.contraDbHttpStatus,
            statusCode: 418,
          ),
        ),
        l10n.importErrorContraDbHttpStatus(418),
      );
    });

    // IMP-06: only an *unclassified* status keeps its code. 404 and 429 (and
    // 5xx) are worded as what to do next, never as "HTTP 4xx".
    test('an unclassified status renders the status code as plain text', () {
      for (final reason in _statusReasons) {
        expect(
          importErrorMessage(l10n, UrlFetchException(reason, statusCode: 418)),
          contains('418'),
        );
      }
    });

    test('404 and 429 messages differ and neither shows an HTTP code', () {
      for (final reason in _statusReasons) {
        final notFound = importErrorMessage(
          l10n,
          UrlFetchException(reason, statusCode: 404),
        );
        final busy = importErrorMessage(
          l10n,
          UrlFetchException(reason, statusCode: 429),
        );
        expect(notFound, isNot(busy), reason: '$reason');
        for (final message in [notFound, busy]) {
          expect(message, isNot(contains('HTTP 4')), reason: '$reason');
          expect(message, isNot(contains('404')), reason: '$reason');
          expect(message, isNot(contains('429')), reason: '$reason');
        }
      }
    });

    test('429 and every 5xx share the "busy, try again" wording', () {
      for (final reason in _statusReasons) {
        final busy = importErrorMessage(
          l10n,
          UrlFetchException(reason, statusCode: 429),
        );
        for (final status in [500, 502, 503, 599]) {
          expect(
            importErrorMessage(
              l10n,
              UrlFetchException(reason, statusCode: status),
            ),
            busy,
            reason: '$reason $status',
          );
        }
        // 4xx other than 404/429 and 3xx are unclassified.
        for (final status in [301, 403, 499, 600]) {
          expect(
            importErrorMessage(
              l10n,
              UrlFetchException(reason, statusCode: status),
            ),
            contains('$status'),
            reason: '$reason $status',
          );
        }
      }
    });

    test('404 and busy use each source\'s own getter', () {
      String msg(UrlFetchFailureReason r, int status) =>
          importErrorMessage(l10n, UrlFetchException(r, statusCode: status));
      expect(
        msg(UrlFetchFailureReason.httpStatus, 404),
        l10n.importErrorHttpNotFound,
      );
      expect(
        msg(UrlFetchFailureReason.httpStatus, 429),
        l10n.importErrorHttpBusy,
      );
      expect(
        msg(UrlFetchFailureReason.callersBoxHttpStatus, 404),
        l10n.importErrorCallersBoxHttpNotFound,
      );
      expect(
        msg(UrlFetchFailureReason.callersBoxHttpStatus, 503),
        l10n.importErrorCallersBoxHttpBusy,
      );
      expect(
        msg(UrlFetchFailureReason.contraDbHttpStatus, 404),
        l10n.importErrorContraDbHttpNotFound,
      );
      expect(
        msg(UrlFetchFailureReason.contraDbHttpStatus, 429),
        l10n.importErrorContraDbHttpBusy,
      );
    });

    test('timeout reasons render the seconds as plain text', () {
      for (final reason in _timeoutReasons) {
        expect(
          importErrorMessage(
            l10n,
            UrlFetchException(reason, timeoutSeconds: 42),
          ),
          contains('42'),
        );
      }
    });

    test('opaque wrapped failures map to a fixed generic string', () {
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.callersBoxNoImportableDance,
          ),
        ),
        l10n.importErrorCallersBoxNoDance,
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(UrlFetchFailureReason.callersBoxImportFailed),
        ),
        l10n.importErrorCallersBoxImportFailed,
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.contraDbNoImportableDance,
          ),
        ),
        l10n.importErrorContraDbNoDance,
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(UrlFetchFailureReason.contraDbImportFailed),
        ),
        l10n.importErrorContraDbImportFailed,
      );
    });

    test('no reason leaks a URL, path, or raw lower-layer error (CWE-209)', () {
      for (final reason in UrlFetchFailureReason.values) {
        final message = importErrorMessage(
          l10n,
          _statusReasons.contains(reason)
              ? UrlFetchException(reason, statusCode: 500)
              : _timeoutReasons.contains(reason)
              ? UrlFetchException(reason, timeoutSeconds: 15)
              : UrlFetchException(reason),
        );
        // No file path or exception/stack tokens leaked into the prose.
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('#0')));
      }
      // The opaque reasons additionally never carry a URL/scheme at all
      // (the generic prose speaks only of the service by name).
      for (final reason in _opaqueReasons) {
        final message = importErrorMessage(l10n, UrlFetchException(reason));
        expect(message.toLowerCase(), isNot(contains('http')));
        expect(message, isNot(contains('://')));
      }
    });

    test(
      'the constructor asserts a dynamic-field reason carries its field',
      () {
        // An HTTP-status reason with no status code, or a timeout reason with
        // no seconds, is a wiring bug the constructor rejects in debug/test
        // builds (asserts on) so it can never reach the mapper as "HTTP 0".
        for (final reason in _statusReasons) {
          expect(
            () => UrlFetchException(reason),
            throwsA(isA<AssertionError>()),
            reason: '$reason must require a statusCode',
          );
        }
        for (final reason in _timeoutReasons) {
          expect(
            () => UrlFetchException(reason),
            throwsA(isA<AssertionError>()),
            reason: '$reason must require timeoutSeconds',
          );
        }
      },
    );
  });

  group('importFileTooLargeMessage', () {
    test('names the cap that applied, not the byte length', () {
      const error = ImportFileTooLargeException(123456789);
      final message = importFileTooLargeMessage(l10n, error);
      expect(message, l10n.importErrorFileTooLarge(25));
      expect(message, contains('25 MB'));
      expect(message, isNot(contains('123456789')));
    });

    test('names the higher .USR cap when that is the one that tripped', () {
      const error = ImportFileTooLargeException(
        300 * 1024 * 1024,
        maxBytes: kMaxImportUsrBytes,
      );
      expect(importFileTooLargeMessage(l10n, error), contains('256 MB'));
    });
  });

  group('attributeFetchFailure', () {
    const status404 = UrlFetchException(
      UrlFetchFailureReason.httpStatus,
      statusCode: 404,
    );
    const offline = UrlFetchException(UrlFetchFailureReason.unreachable);
    const timeout30 = UrlFetchException(
      UrlFetchFailureReason.timeout,
      timeoutSeconds: 30,
    );
    const empty = UrlFetchException(UrlFetchFailureReason.emptyResponse);

    test('Caller\'s Box: httpStatus and unreachable take its own reasons', () {
      final status = attributeFetchFailure(
        status404,
        ImportSourceKind.callersBox,
      );
      expect(status.reason, UrlFetchFailureReason.callersBoxHttpStatus);
      expect(status.statusCode, 404);
      expect(
        attributeFetchFailure(offline, ImportSourceKind.callersBox).reason,
        UrlFetchFailureReason.callersBoxUnreachable,
      );
    });

    test('ContraDB: httpStatus and unreachable take its own reasons', () {
      final status = attributeFetchFailure(
        status404,
        ImportSourceKind.contraDb,
      );
      expect(status.reason, UrlFetchFailureReason.contraDbHttpStatus);
      expect(status.statusCode, 404);
      expect(
        attributeFetchFailure(offline, ImportSourceKind.contraDb).reason,
        UrlFetchFailureReason.contraDbUnreachable,
      );
    });

    test('every other source, and every other reason, is unchanged', () {
      for (final kind in ImportSourceKind.values) {
        if (kind == ImportSourceKind.callersBox ||
            kind == ImportSourceKind.contraDb) {
          continue;
        }
        expect(attributeFetchFailure(status404, kind), same(status404));
        expect(attributeFetchFailure(offline, kind), same(offline));
        expect(attributeFetchFailure(timeout30, kind), same(timeout30));
        expect(attributeFetchFailure(empty, kind), same(empty));
      }
      // Generic sources keep the generic wording.
      expect(
        importErrorMessage(
          l10n,
          attributeFetchFailure(timeout30, ImportSourceKind.genericJson),
        ),
        l10n.importErrorTimeout(30),
      );
      expect(
        importErrorMessage(
          l10n,
          attributeFetchFailure(empty, ImportSourceKind.genericJson),
        ),
        l10n.importErrorEmptyResponse,
      );
      const blocked = UrlFetchException(UrlFetchFailureReason.blockedHost);
      for (final kind in [
        ImportSourceKind.callersBox,
        ImportSourceKind.contraDb,
      ]) {
        expect(attributeFetchFailure(blocked, kind), same(blocked));
      }
    });

    // backupimport-2 (CS-21): an id or link for The Caller's Box / ContraDB
    // that times out or comes back empty names the source, never "the URL".
    test("Caller's Box: a timeout names the source and keeps the seconds", () {
      final mapped = attributeFetchFailure(
        timeout30,
        ImportSourceKind.callersBox,
      );
      expect(mapped.reason, UrlFetchFailureReason.callersBoxTimeout);
      expect(mapped.timeoutSeconds, 30);
      final message = importErrorMessage(l10n, mapped);
      expect(
        message,
        "The Caller's Box didn't respond within 30s. "
        'Check your connection, then try again.',
      );
      expect(message, isNot(contains('URL')));
    });

    test('ContraDB: a timeout names the source and keeps the seconds', () {
      final mapped = attributeFetchFailure(
        timeout30,
        ImportSourceKind.contraDb,
      );
      expect(mapped.reason, UrlFetchFailureReason.contraDbTimeout);
      expect(mapped.timeoutSeconds, 30);
      final message = importErrorMessage(l10n, mapped);
      expect(
        message,
        "ContraDB didn't respond within 30s. "
        'Check your connection, then try again.',
      );
      expect(message, isNot(contains('URL')));
    });

    test("Caller's Box: an empty response takes its empty-page reason", () {
      final mapped = attributeFetchFailure(empty, ImportSourceKind.callersBox);
      expect(mapped.reason, UrlFetchFailureReason.callersBoxEmptyPage);
      final message = importErrorMessage(l10n, mapped);
      expect(
        message,
        "The Caller's Box returned an empty page. Try again in a minute.",
      );
      expect(message, isNot(contains('URL')));
    });

    test('ContraDB: an empty response takes its empty-response reason', () {
      final mapped = attributeFetchFailure(empty, ImportSourceKind.contraDb);
      expect(mapped.reason, UrlFetchFailureReason.contraDbEmptyResponse);
      final message = importErrorMessage(l10n, mapped);
      expect(
        message,
        'ContraDB returned an empty response. Try again in a minute.',
      );
      expect(message, isNot(contains('URL')));
    });
  });

  group('importSourceLabel', () {
    test('maps every kind to its localized label', () {
      expect(
        importSourceLabel(l10n, ImportSourceKind.genericJson),
        l10n.importSourceLabelGenericJson,
      );
      expect(
        importSourceLabel(l10n, ImportSourceKind.callersBox),
        l10n.importSourceLabelCallersBox,
      );
      expect(
        importSourceLabel(l10n, ImportSourceKind.contraDb),
        l10n.importSourceLabelContraDb,
      );
      expect(
        importSourceLabel(l10n, ImportSourceKind.callersCompanionUsr),
        l10n.importSourceLabelCallersCompanionUsr,
      );
    });

    test('every kind yields a non-empty label', () {
      for (final kind in ImportSourceKind.values) {
        expect(importSourceLabel(l10n, kind), isNotEmpty);
      }
    });
  });
}
