// A square's free-form toggle (ADR-007 §8.1): `Dance.freeForm` is the
// caller's setting, or null to follow the kind (on for patter, off for the
// others), and `Dance.isFreeForm` is what applies. A free-form dance has no
// phrase sections and no phrase checks, and keeps its phrase structure
// unused. The field joined the unreleased schema v42 and archive v8, is kept
// for every form, and a dance that leaves it unset encodes exactly as it did
// before it existed.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveDanceToJson;
import 'package:compendium_core/testing.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

Figure _fig(int beats) => testFigure(move: 'swing', params: {'beats': beats});

/// A square whose figures cross phrase lines and miss the phrase total, so a
/// phrased square warns about both.
Dance _square({SquareKind kind = SquareKind.main, bool? freeForm}) =>
    sampleDance().copyWith(
      form: DanceForm.square,
      squareKind: kind,
      freeForm: freeForm,
      figures: [_fig(12), _fig(8), _fig(6)],
    );

Map<String, Object?> _danceJson(Dance dance) =>
    archiveDanceToJson(dance, const {}, includeOptionalFields: true);

void main() {
  group('model', () {
    test('left unset, a square follows its kind: only patter is free '
        'form', () {
      expect(sampleDance().freeForm, isNull);
      expect(_square().isFreeForm, isFalse);
      expect(_square(kind: SquareKind.breakPart).isFreeForm, isFalse);
      expect(_square(kind: SquareKind.patter).isFreeForm, isTrue);
    });

    test("the caller's setting wins over the kind either way", () {
      expect(_square(freeForm: true).isFreeForm, isTrue);
      expect(
        _square(kind: SquareKind.patter, freeForm: false).isFreeForm,
        isFalse,
      );
    });

    test('only a square is free form, but every form keeps the setting', () {
      final square = _square(freeForm: true);
      final contra = square.copyWith(form: DanceForm.contra);
      expect(contra.freeForm, isTrue);
      expect(contra.isFreeForm, isFalse);
      expect(contra.copyWith(form: DanceForm.square), square);
    });

    test('copyWith keeps it, clearFreeForm hands it back to the kind, and '
        'duplicate and equality carry it', () {
      final dance = _square(freeForm: false);
      expect(dance.copyWith(title: 'Other').freeForm, isFalse);
      expect(dance.copyWith(clearFreeForm: true).freeForm, isNull);
      expect(
        dance.duplicate(newId: 'copy', now: DateTime.utc(2026, 2)).freeForm,
        isFalse,
      );
      expect(dance, isNot(dance.copyWith(freeForm: true)));
      expect(dance, isNot(dance.copyWith(clearFreeForm: true)));
    });
  });

  group('phrasing', () {
    test('a free-form dance has no section labels, but its start beats are '
        'still counted', () {
      final sections = _square(freeForm: true).sectionedFigures;
      expect(sections.map((s) => s.label), ['', '', '']);
      expect(sections.map((s) => s.startBeat), [0, 12, 20]);
      expect(_square().sectionedFigures.map((s) => s.label), [
        'A1',
        'A1',
        'A2',
      ]);
    });

    test('a free-form dance raises no phrase warning; the same figures '
        'phrased raise both', () {
      expect(
        _square().validate().map((i) => i.code),
        containsAll([figureCrossesPhraseCode, 'phrase_underflow']),
      );
      expect(_square(freeForm: true).validate(), isEmpty);
      expect(_square(kind: SquareKind.patter).validate(), isEmpty);
    });

    test('deriveSections ignores the structure and checkPhraseFill when free '
        'form', () {
      final issues = <ValidationIssue>[];
      final sections = deriveSections(
        [_fig(12), _fig(8)],
        PhraseStructure.parse('6*8*2'),
        issues: issues,
        checkPhraseFill: true,
        freeForm: true,
      );
      expect(issues, isEmpty);
      expect(sections.map((s) => (s.index, s.startBeat, s.label)), [
        (0, 0, ''),
        (1, 12, ''),
      ]);
    });

    test('a free-form dance is measured against one phrase longer than any '
        'dance', () {
      final unphrased = PhraseStructure.unphrased;
      expect(unphrased, PhraseStructure.parse(unphrased.raw));
      expect(
        unphrased.phraseBeatsAt(0),
        PhraseStructure.maxComponentNumber * 4,
      );
      expect(unphrased.phraseBeatsAt(1000), unphrased.phraseBeatsAt(0));
    });

    test('the text export leads with no phrase label', () {
      final text = danceToPlainText(
        _square(freeForm: true),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Square',
        statusLabel: 'Active',
      );
      final figureLines = text
          .split('\n')
          .where((line) => line.contains(' beats)'))
          .toList();
      expect(figureLines, hasLength(3));
      for (final line in figureLines) {
        expect(line, isNot(startsWith(' ')));
        expect(line, isNot(contains('A1')));
      }
    });
  });

  group('elsewhere', () {
    test('a free-form dance prints no phrase line, though it keeps the '
        'structure', () {
      final dance = _square(freeForm: true).copyWith(phraseStructure: '6*8*2');
      String text(Dance d) => danceToPlainText(
        d,
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Square',
        statusLabel: 'Active',
      );
      expect(dance.phraseStructure.raw, '6*8*2');
      expect(text(dance), isNot(contains('Phrase')));
      expect(text(dance.copyWith(freeForm: false)), contains('Phrase'));
    });

    test("the import review's figure diff gives a free-form side no "
        'phrase', () {
      FigureDiffResult diff({required bool freeForm}) => diffFigures(
        oldFigures: [_fig(12)],
        oldStructure: PhraseStructure.standard,
        newFigures: [_fig(12), _fig(8)],
        newStructure: PhraseStructure.standard,
        taxonomy: shippedTaxonomies.anyForm,
        renderer: FigureRenderer(shippedTaxonomies.anyForm),
        dialect: Dialect.canonical,
        newFreeForm: freeForm,
      );
      expect(
        diff(freeForm: false).entries.map((e) => e.phraseLabel),
        contains('A1'),
      );
      expect(
        diff(freeForm: true).entries.map((e) => e.phraseLabel),
        everyElement(''),
      );
    });
  });

  group('archive', () {
    test('round-trips each setting', () {
      for (final freeForm in [true, false]) {
        final dance = _square(freeForm: freeForm);
        final read = decodeArchive(
          encodeArchive(
            CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
          ),
        );
        expect(read.errors, isEmpty);
        expect(read.archive.dances.single.freeForm, freeForm);
      }
    });

    test('a dance that leaves it unset writes no key and keeps its earlier '
        'stamp; setting it either way stamps v8', () {
      final unset = _square();
      expect(_danceJson(unset).keys, isNot(contains('freeForm')));
      expect(
        requiredSchemaVersion(
          CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [unset]),
        ),
        lessThan(archiveSchemaVersionEcdDanceFields),
      );
      for (final freeForm in [true, false]) {
        expect(
          requiredSchemaVersion(
            CompendiumArchive(
              exportedAt: DateTime.utc(2026),
              dances: [_square(freeForm: freeForm)],
            ),
          ),
          archiveSchemaVersionEcdDanceFields,
          reason: '$freeForm',
        );
      }
    });

    test('a file without the key reads it as unset', () {
      final body = _danceJson(_square(freeForm: true))..remove('freeForm');
      final read = decodeArchive(
        jsonEncode({
          'schemaVersion': archiveSchemaVersionEcdDanceFields,
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'dances': [body],
        }),
      );
      expect(read.errors, isEmpty);
      expect(read.archive.dances.single.freeForm, isNull);
    });
  });

  group('sync', () {
    SyncRecordBlob blobOf(Dance dance) => syncRecordBlobForEntity(
      SyncRecordKind.dance,
      dance,
      updatedAt: dance.updatedAt,
      existenceAt: dance.updatedAt,
    )!;

    test('a body that leaves it out sets it back to unset when applied', () {
      final blob = blobOf(_square());
      expect(blob.body.keys, isNot(contains('freeForm')));
      // Filled in as null, not merely missing: a missing key keeps the value
      // the receiver has, so a choice cleared on one device would stay on
      // the others.
      final known = syncInboundKnownBody(blob);
      expect(known.containsKey('freeForm'), isTrue);
      expect(known['freeForm'], isNull);
    });

    test('a body that carries it keeps it, false as well as true', () {
      expect(
        syncInboundKnownBody(blobOf(_square(freeForm: false)))['freeForm'],
        false,
      );
      expect(
        syncInboundKnownBody(blobOf(_square(freeForm: true)))['freeForm'],
        true,
      );
    });

    test('the choreography fingerprint ignores it, as an older build '
        'does', () {
      expect(
        choreographyFingerprintForDance(_square(freeForm: true)),
        choreographyFingerprintForDance(_square()),
      );
    });
  });

  group('storage', () {
    test('a dance round-trips each setting, and clearing it sticks', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final dance = _square(freeForm: false);
      await dances.create(dance);
      expect(await dances.getById(dance.id), dance);
      final on = dance.copyWith(
        freeForm: true,
        updatedAt: DateTime.utc(2026, 3),
      );
      await dances.update(on);
      expect(await dances.getById(dance.id), on);
      final cleared = on.copyWith(
        clearFreeForm: true,
        updatedAt: DateTime.utc(2026, 4),
      );
      await dances.update(cleared);
      expect((await dances.getById(dance.id))!.freeForm, isNull);
    });

    test('the figure index gives a free-form dance no sections', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final dance = _square(freeForm: true).copyWith(
        figures: [
          _fig(12),
          Figure.sequence(figures: [_fig(8), _fig(8)], beats: 16),
        ],
      );
      await dances.create(dance);
      final sections = await db
          .customSelect(
            'SELECT DISTINCT section FROM dance_figures WHERE dance_id = ?',
            variables: [Variable.withString(dance.id)],
          )
          .map((row) => row.read<String>('section'))
          .get();
      expect(sections, ['']);
    });
  });
}
