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
            statusCode: 503,
          ),
        ),
        l10n.importErrorHttpStatus(503),
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.callersBoxHttpStatus,
            statusCode: 503,
          ),
        ),
        l10n.importErrorCallersBoxHttpStatus(503),
      );
      expect(
        importErrorMessage(
          l10n,
          const UrlFetchException(
            UrlFetchFailureReason.contraDbHttpStatus,
            statusCode: 503,
          ),
        ),
        l10n.importErrorContraDbHttpStatus(503),
      );
    });

    test('status reasons render the status code as plain text', () {
      for (final reason in _statusReasons) {
        expect(
          importErrorMessage(l10n, UrlFetchException(reason, statusCode: 418)),
          contains('418'),
        );
      }
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
    test('returns the generic too-large string without the byte length', () {
      const error = ImportFileTooLargeException(123456789);
      final message = importFileTooLargeMessage(l10n, error);
      expect(message, l10n.importErrorFileTooLarge);
      expect(message, isNot(contains('123456789')));
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
