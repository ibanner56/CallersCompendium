// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Every adapter's discover-time failure carries a typed [ImportErrorCode], so
/// the UI can say what was wrong without rendering [ImportError.message]
/// (CWE-209).
Matcher _importError(ImportErrorCode code, {ImportStage? stage}) =>
    isA<ImportError>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.stage, 'stage', stage ?? ImportStage.discover);

void main() {
  test('a bare ImportError defaults to ImportErrorCode.unknown', () {
    const error = ImportError(
      stage: ImportStage.parse,
      source: ProvenanceSource.contradb,
      message: 'x',
    );
    expect(error.code, ImportErrorCode.unknown);
    expect(
      error.copyWith(code: ImportErrorCode.notJson).code,
      ImportErrorCode.notJson,
    );
    expect(error.copyWith(message: 'y').code, ImportErrorCode.unknown);
  });

  test('CallersCompanionTextAdapter: empty payload → emptyFile', () {
    expect(
      () => CallersCompanionTextAdapter().discover(
        const ImportRequest(payload: '  '),
      ),
      throwsA(_importError(ImportErrorCode.emptyFile)),
    );
  });

  group('GenericJsonAdapter', () {
    test('missing payload → emptyFile', () {
      expect(
        () => GenericJsonAdapter().discover(const ImportRequest()),
        throwsA(_importError(ImportErrorCode.emptyFile)),
      );
    });

    test('not an archive → notCompendiumArchive', () {
      expect(
        () => GenericJsonAdapter().discover(
          const ImportRequest(payload: 'hello'),
        ),
        throwsA(_importError(ImportErrorCode.notCompendiumArchive)),
      );
    });
  });

  group('CallersBoxAdapter', () {
    Future<void> expectCode(String? payload, ImportErrorCode code) async {
      await expectLater(
        CallersBoxAdapter().discover(ImportRequest(payload: payload)),
        throwsA(_importError(code)),
      );
    }

    test(
      'empty payload → emptyFile',
      () => expectCode('  ', ImportErrorCode.emptyFile),
    );
    test(
      'not JSON → notJson',
      () => expectCode('{not json', ImportErrorCode.notJson),
    );
    test(
      'wrong shape → notCallersBoxDance',
      () => expectCode('{"foo": "bar"}', ImportErrorCode.notCallersBoxDance),
    );
    test(
      'no dance element → noDanceAtId',
      () => expectCode('[]', ImportErrorCode.noDanceAtId),
    );
  });

  group('ContraDbAdapter', () {
    Future<void> expectCode(String? payload, ImportErrorCode code) async {
      await expectLater(
        ContraDbAdapter().discover(ImportRequest(payload: payload)),
        throwsA(_importError(code)),
      );
    }

    test(
      'empty payload → emptyFile',
      () => expectCode(null, ImportErrorCode.emptyFile),
    );
    test(
      'not JSON → notJson',
      () => expectCode('{not json', ImportErrorCode.notJson),
    );
    test(
      'wrong shape → notContraDbDance',
      () => expectCode('"hello"', ImportErrorCode.notContraDbDance),
    );
  });

  group('ContraDbHtmlAdapter', () {
    test('empty payload → emptyFile', () {
      expect(
        () =>
            ContraDbHtmlAdapter().discover(const ImportRequest(payload: '   ')),
        throwsA(_importError(ImportErrorCode.emptyFile)),
      );
    });

    test('not a dance page → notContraDbDance', () {
      expect(
        () => ContraDbHtmlAdapter().discover(
          const ImportRequest(payload: '<p>some other page</p>'),
        ),
        throwsA(_importError(ImportErrorCode.notContraDbDance)),
      );
    });
  });

  group('CallersCompanionUsrAdapter', () {
    test('random bytes → notUsrDatabase', () {
      expect(
        () => CallersCompanionUsrAdapter().discover(
          ImportRequest(
            options: {'bytes': Uint8List.fromList(List<int>.filled(64, 0x41))},
          ),
        ),
        throwsA(_importError(ImportErrorCode.notUsrDatabase)),
      );
    });

    test('invalid base64 → notUsrDatabase', () {
      expect(
        () => CallersCompanionUsrAdapter().discover(
          const ImportRequest(payload: 'not valid base64 !!!'),
        ),
        throwsA(_importError(ImportErrorCode.notUsrDatabase)),
      );
    });

    test('no file → emptyFile', () {
      expect(
        () => CallersCompanionUsrAdapter().discover(const ImportRequest()),
        throwsA(_importError(ImportErrorCode.emptyFile)),
      );
    });

    test('over the resource limits → fileTooLarge (discover)', () {
      final adapter = CallersCompanionUsrAdapter(
        reader: (bytes, limits) =>
            throw const FmpResourceLimitException('too many records'),
      );
      expect(
        () => adapter.discover(ImportRequest(options: {'bytes': Uint8List(8)})),
        throwsA(_importError(ImportErrorCode.fileTooLarge)),
      );
    });
  });

  group('ImportPipeline.plan', () {
    ImportPipeline pipeline(CompendiumDatabase db) => ImportPipeline(
      DanceRepository(db, contraTaxonomy),
      ChoreographerRepository(db),
    );

    test('returns an adapter ImportError as-is, code included', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final result = await pipeline(
        db,
      ).plan(GenericJsonAdapter(), const ImportRequest(payload: 'hello'));
      expect(result.errors, hasLength(1));
      expect(
        result.errors.single,
        _importError(ImportErrorCode.notCompendiumArchive),
      );
    });

    test('wraps any other failure as unknown', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final result = await pipeline(db).plan(
        CallersCompanionUsrAdapter(
          reader: (bytes, limits) => throw StateError('boom'),
        ),
        ImportRequest(options: {'bytes': Uint8List(8)}),
      );
      expect(result.errors.single.code, ImportErrorCode.unknown);
      expect(result.errors.single.stage, ImportStage.discover);
    });
  });
}
