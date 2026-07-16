import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Fixtures + tests for [CallersCompanionTextAdapter]: Caller's Companion's
/// "copy formatted dance" clipboard/text export as a per-dance import source.
///
/// The text fixtures below are **synthetic**, faithful to the assumed format
/// documented on [CallersCompanionTextAdapter] and grounded in the CC schema
/// survey (`docs/research/callers-companion.md`: fields Name/Author/Type/
/// Formation/Level/Progression/Music/dates; free-text body sections
/// A1/A2/B1/B2 with `(beats) text` lines). No real CC clipboard sample exists.

const _fullDance = '''
Simplicity Swing
by Becky Hill
Type: Contra
Formation: Improper
Level: Intermediate
Progression: Single
Music: any good 32-bar reels
Composed: 2004

A1   (8) Neighbor balance and swing
     (8) Circle left 3/4
A2   (16) Partner balance and swing
B1   (8) Long lines forward and back
     (8) Ladies chain
B2   (16) Hey for four
''';

Future<StructuredDraft> _importOne(
  CallersCompanionTextAdapter adapter,
  DiscoveredRecord record,
) async {
  final raw = await adapter.fetch(record);
  return adapter.parse(raw);
}

Future<List<StructuredDraft>> _importAll(
  CallersCompanionTextAdapter adapter,
  String payload,
) async {
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  return [for (final r in discovered) await _importOne(adapter, r)];
}

void main() {
  late CallersCompanionTextAdapter adapter;

  setUp(() => adapter = CallersCompanionTextAdapter());

  group('CallersCompanionTextAdapter', () {
    test('source is ProvenanceSource.callersCompanion', () {
      expect(adapter.source, ProvenanceSource.callersCompanion);
    });

    test('discover throws on a missing/empty payload', () {
      expect(
        () => adapter.discover(const ImportRequest(payload: '   ')),
        throwsA(
          isA<ImportError>()
              .having((e) => e.stage, 'stage', ImportStage.discover)
              .having((e) => e.source, 'source', adapter.source),
        ),
      );
    });

    test('parses a full dance: header fields, dates, and figures', () async {
      final drafts = await _importAll(adapter, _fullDance);
      expect(drafts, hasLength(1));
      final dance = drafts.single.dance;

      expect(dance.title, 'Simplicity Swing');
      expect(dance.level, DanceLevel.intermediate);
      expect(dance.mixedLevel, isFalse);
      expect(dance.formation.shape, FormationShape.dupleImproper);
      expect(dance.progression, Progression.single);
      expect(dance.form, DanceForm.contra);
      expect(dance.composedOn, PartialDate(2004));
      expect(dance.callingNotes, contains('Music: any good 32-bar reels'));

      // Every figure is custom (design §2) and carries its beats + section.
      expect(dance.figures, hasLength(6));
      expect(dance.figures.every((f) => f.isCustom), isTrue);
      expect(dance.figures.first.beats, 8);
      expect(
        dance.figures.first.params['text'],
        'A1: Neighbor balance and swing',
      );
      final swing = dance.figures[2];
      expect(swing.beats, 16);
      expect(swing.params['text'], 'A2: Partner balance and swing');
    });

    test('quality is fully custom for a CC dance', () async {
      final draft = (await _importAll(adapter, _fullDance)).single;
      expect(draft.quality.isFullyCustom, isTrue);
      expect(draft.quality.score, 0.0);
    });

    test('author name surfaces as an unresolved-author issue', () async {
      final draft = (await _importAll(adapter, _fullDance)).single;
      // No fabricated author ids — the name is conveyed for review instead.
      expect(draft.dance.authorIds, isEmpty);
      final authorIssues = draft.issues.where(
        (i) => i.code == 'cc_unresolved_author',
      );
      expect(authorIssues, hasLength(1));
      expect(authorIssues.single.message, contains('Becky Hill'));
    });

    test('a body line with no beats prefix imports with beats 0', () async {
      const text = '''
No Beats Dance
A1 Balance the ring
   (8) Petronella turn
''';
      final draft = (await _importAll(adapter, text)).single;
      expect(draft.dance.figures, hasLength(2));
      expect(draft.dance.figures[0].beats, 0);
      expect(draft.dance.figures[0].params['text'], 'A1: Balance the ring');
      expect(draft.dance.figures[1].beats, 8);
    });

    test(
      'a dance missing a title gets a placeholder + warning, not a throw',
      () async {
        // No recognizable header title, but real body content → still a dance.
        const text = '''
(16) Neighbor balance and swing
(8) Circle left 3/4
''';
        final draft = (await _importAll(adapter, text)).single;
        expect(draft.dance.title, ccUntitledDanceTitle);
        expect(
          draft.issues.where((i) => i.code == 'cc_missing_title'),
          hasLength(1),
        );
        expect(draft.dance.figures, hasLength(2));
      },
    );

    test(
      'multi-dance paste (form-feed separated) yields one record each',
      () async {
        final payload =
            '$_fullDance\f${'''
Other Dance
by Cary Ravitz
Level: Advanced

A1 (16) Circle left and right
'''}';
        final drafts = await _importAll(adapter, payload);
        expect(drafts, hasLength(2));
        expect(drafts[0].dance.title, 'Simplicity Swing');
        expect(drafts[1].dance.title, 'Other Dance');
        expect(drafts[1].dance.level, DanceLevel.advanced);
      },
    );

    test('unmapped level and formation surface warnings', () async {
      const text = '''
Weird Dance
Level: Sizzling
Formation: Hexagon

A1 (8) Do the thing
''';
      final draft = (await _importAll(adapter, text)).single;
      expect(draft.dance.level, isNull);
      expect(draft.dance.formation.shape, FormationShape.other);
      expect(draft.dance.formation.detail, 'Hexagon');
      expect(
        draft.issues.map((i) => i.code),
        containsAll(<String>['cc_unmapped_level', 'cc_unmapped_formation']),
      );
    });

    test('a "mixed" level sets mixedLevel rather than a scale point', () async {
      const text = '''
Mixed Level Medley
Level: Mixed

A1 (8) Do the thing
''';
      final draft = (await _importAll(adapter, text)).single;
      expect(draft.dance.level, isNull);
      expect(draft.dance.mixedLevel, isTrue);
    });

    test('parse throws on an unrecognizable block', () async {
      final raw = RawRecord(
        source: adapter.source,
        payload: '   \n  \n',
        contentType: 'text/plain',
      );
      expect(
        () => adapter.parse(raw),
        throwsA(
          isA<ImportError>().having((e) => e.stage, 'stage', ImportStage.parse),
        ),
      );
    });
  });

  group('through ImportPipeline.plan', () {
    late CompendiumDatabase db;
    late ImportPipeline pipeline;

    setUp(() {
      db = openTestDatabase();
      pipeline = ImportPipeline(
        DanceRepository(db, contraTaxonomy),
        ChoreographerRepository(db),
      );
    });

    tearDown(() => db.close());

    test('a garbage block is skipped while good blocks still plan', () async {
      // Two blocks: a valid dance and a whitespace-only garbage block.
      final payload = '$_fullDance\f   \n  ';
      final result = await pipeline.plan(
        adapter,
        ImportRequest(payload: payload),
      );
      // The blank block is dropped at discover, so only the good dance plans.
      expect(result.plannedCount, 1);
      expect(result.records.single.draft.dance.title, 'Simplicity Swing');
    });

    test('an empty payload surfaces a structured discover error', () async {
      final result = await pipeline.plan(
        adapter,
        const ImportRequest(payload: ''),
      );
      expect(result.plannedCount, 0);
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.stage, ImportStage.discover);
    });

    test('null externalId → re-pasting the same dance is a new-dance verdict '
        'against an empty collection, and fuzzy-matches once present', () async {
      final first = await pipeline.plan(
        adapter,
        ImportRequest(payload: _fullDance),
      );
      expect(first.records.single.verdict.isNewDance, isTrue);

      // Commit it, then re-plan the identical paste: with no stable externalId,
      // dedupe falls to fuzzy title+author and flags an ambiguous match rather
      // than a silent re-import.
      await pipeline.commit(
        first,
        now: DateTime.utc(2026, 7, 15),
        newId: () => 'cc-1',
      );
      final second = await pipeline.plan(
        adapter,
        ImportRequest(payload: _fullDance),
      );
      expect(second.records.single.verdict.isReimport, isFalse);
      expect(second.records.single.verdict.isAmbiguous, isTrue);
    });
  });
}
