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

/// Answers every search with one row per name in [names].
class _RowsService extends _ThrowingService {
  _RowsService(this.names) : super(StateError('unused'));

  final List<String> names;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async => [
    for (final (i, name) in names.indexed)
      OnlineSearchResultRow(
        source: OnlineSource.callersBox,
        id: '$i',
        name: name,
        author: '',
        formation: '',
      ),
  ];
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

  group('lookupUniqueExactTitle title matching', () {
    Future<OnlineTitleLookupResult> lookup(String title, List<String> names) =>
        lookupUniqueExactTitle(title, service: _RowsService(names));

    test('a curly apostrophe matches the straight one stored', () async {
      final outcome = await lookup('Rory O’More', ["Rory O'More"]);
      expect((outcome as OnlineTitleHit).row.name, "Rory O'More");
    });

    test('a straight quote matches curly quotes stored', () async {
      final outcome = await lookup('"revolving  poussette"', [
        '“Revolving Poussette”',
      ]);
      expect(outcome, isA<OnlineTitleHit>());
    });

    test('two rows differing only in quote style are ambiguous', () async {
      final outcome = await lookup("Anna's Reel", [
        "Anna's Reel",
        'Anna’s Reel',
      ]);
      expect(
        (outcome as OnlineTitleMiss).failure,
        OnlineTitleLookupFailure.multipleExactMatches,
      );
    });

    test('dropping the apostrophe is still not an exact match', () async {
      final outcome = await lookup('Rory OMore', ["Rory O'More"]);
      expect(
        (outcome as OnlineTitleMiss).failure,
        OnlineTitleLookupFailure.noExactMatch,
      );
    });
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
