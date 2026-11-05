import 'dart:io';

import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/published_collections/published_collection_service.dart';
import 'package:compendium_app/src/sync/sync_failure.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CrashLogRecord.messageSafeErrorTypes` names app-package classes as strings
/// (core cannot import them). This pins each name to the class it means, so a
/// rename cannot silently start withholding a message, or leave a stale name
/// that would later match an unrelated class.
void main() {
  test('every allow-listed name is a real class in the app', () {
    final real = <String, String>{
      'UrlFetchException': const UrlFetchException(
        UrlFetchFailureReason.timeout,
        timeoutSeconds: 30,
      ).runtimeType.toString(),
      'PublishedCollectionFetchException':
          const PublishedCollectionFetchException(
            PublishedCollectionFetchFailure.unavailable,
          ).runtimeType.toString(),
    };
    // The download error is private to update_controller.dart, so check the
    // declaration itself rather than export the class for a test.
    final controller = File(
      'lib/src/update/update_controller.dart',
    ).readAsStringSync();
    expect(controller, contains('class _UpdateDownloadError implements'));
    real['_UpdateDownloadError'] = '_UpdateDownloadError';

    expect(real.keys.toSet(), CrashLogRecord.messageSafeErrorTypes);
    for (final entry in real.entries) {
      expect(entry.value, entry.key);
    }
  });

  // `SyncFailure` was listed here once, but it is returned rather than thrown,
  // so it never reaches the crash log. The type that does is
  // `SyncWorkerFailure`, and its message is the worker's free text.
  test('the thrown Device Sync failure keeps its message withheld', () {
    final thrown = SyncWorkerFailure(
      'GET https://sync.example.com/stores/abc failed',
      SyncFailureCause.unreachable,
    );
    expect(
      CrashLogRecord.messageSafeErrorTypes,
      isNot(contains(thrown.runtimeType.toString())),
    );
  });

  test('the typed messages that survive carry no URL, path or prose', () {
    final messages = [
      const UrlFetchException(
        UrlFetchFailureReason.httpStatus,
        statusCode: 404,
      ).toString(),
      const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.digestMismatch,
      ).toString(),
    ];
    for (final message in messages) {
      expect(message, isNot(contains('/')), reason: message);
      expect(message, isNot(contains('://')), reason: message);
    }
  });
}
