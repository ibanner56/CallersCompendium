import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/online_title_lookup.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingService implements OnlineSearchService {
  _ThrowingService(this.error);

  final Object error;

  @override
  OnlineSource get source => OnlineSource.callersBox;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async =>
      throw error;

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) => throw UnimplementedError();

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
    List<String> defaultTagIds = const [],
  }) => throw UnimplementedError();
}

Future<OnlineTitleLookupFailure> _failureFor(Object error) async {
  final outcome = await lookupUniqueExactTitle(
    'Any Title',
    service: _ThrowingService(error),
  );
  return (outcome as OnlineTitleMiss).failure;
}

void main() {
  group('lookupUniqueExactTitle transport failures', () {
    test('a connection-class UrlFetchException is unreachable', () async {
      expect(
        await _failureFor(
          const UrlFetchException(UrlFetchFailureReason.callersBoxUnreachable),
        ),
        OnlineTitleLookupFailure.unreachable,
      );
      expect(
        await _failureFor(
          const UrlFetchException(
            UrlFetchFailureReason.searchTimeout,
            timeoutSeconds: 30,
          ),
        ),
        OnlineTitleLookupFailure.unreachable,
      );
      // The source-attributed timeouts (CS-21) stay connection-class too.
      for (final reason in [
        UrlFetchFailureReason.callersBoxTimeout,
        UrlFetchFailureReason.contraDbTimeout,
      ]) {
        expect(
          await _failureFor(UrlFetchException(reason, timeoutSeconds: 30)),
          OnlineTitleLookupFailure.unreachable,
        );
      }
      expect(
        await _failureFor(
          const UrlFetchException(
            UrlFetchFailureReason.callersBoxHttpStatus,
            statusCode: 503,
          ),
        ),
        OnlineTitleLookupFailure.unreachable,
      );
    });

    test(
      'a plain Exception or a non-transport reason stays fetchError',
      () async {
        expect(
          await _failureFor(Exception('x')),
          OnlineTitleLookupFailure.fetchError,
        );
        expect(
          await _failureFor(
            const UrlFetchException(UrlFetchFailureReason.callersBoxEmptyPage),
          ),
          OnlineTitleLookupFailure.fetchError,
        );
      },
    );
  });

  test('isConnectionFailure: HTTP-status reasons only when asked for', () {
    const preview = UrlFetchException(
      UrlFetchFailureReason.httpStatus,
      statusCode: 404,
    );
    const search = UrlFetchException(
      UrlFetchFailureReason.callersBoxHttpStatus,
      statusCode: 500,
    );
    expect(isConnectionFailure(search), isFalse);
    expect(isConnectionFailure(search, includeHttpStatus: true), isTrue);
    expect(isConnectionFailure(preview, includeHttpStatus: true), isFalse);
    expect(
      isConnectionFailure(
        const UrlFetchException(UrlFetchFailureReason.unreachable),
      ),
      isTrue,
    );
    expect(isConnectionFailure(StateError('x')), isFalse);
  });
}
