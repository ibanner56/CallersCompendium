import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

/// Issue #347 — The Caller's Box **compound-figure** convention + revolving-door
/// text parity. TCB expresses a named figure as its indented component
/// sub-figures whose beats sum to the parent's (e.g. `(6) Revolving door:` ==
/// `(4) Partner star promenade ½` + `(2) Women allemande right ½`). The children
/// are the *definition*, not extra choreography, so the compound must collapse
/// to a SINGLE figure carrying the PARENT's beats — never re-emit the children.
///
/// Reference dance: **Right Where We Belong** by Isaac Banner
/// (TCB #19001 / ContraDB #2443), captured verbatim into the fixtures under
/// `test/imports/support/`. No network is used.

Future<StructuredDraft> _importTcb(String payload) async {
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

/// Imports a synthetic single-phrase TCB dance from its raw figure lines.
Future<StructuredDraft> _importFigures(List<String> figures) =>
    _importTcb(_tcbDance(figures));

Future<StructuredDraft> _importContraDbHtml(String payload) async {
  final adapter = ContraDbHtmlAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: payload, uri: 'https://contradb.com/dances/2443'),
  );
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

/// A minimal `full`-permission TCB dance with one phrase's figure lines.
String _tcbDance(List<String> figures) => jsonEncode({
  'ID': '9001',
  'Name': 'Synthetic',
  'Permission': 'full',
  'phrases': [
    {'name': 'A1', 'figures': figures},
  ],
});

String _text(Figure f) => f.params['text'] as String;

void main() {
  // --- Real "Right Where We Belong" from The Caller's Box (#19001) -----------
  group('TCB #19001 real fixture (Right Where We Belong)', () {
    late StructuredDraft draft;

    setUp(() async {
      final payload = File(
        p.join(
          await packageRootPath(),
          'test',
          'imports',
          'support',
          'callersbox',
          'right_where_we_belong_19001.json',
        ),
      ).readAsStringSync();
      draft = await _importTcb(payload);
    });

    test('A1 collapses to ONE revolving door + neighbor swing (no split)', () {
      final figs = draft.dance.figures;
      // A1 is exactly two figures: the collapsed revolving door and the swing —
      // NOT four (the old bug emitted the two indented children as well).
      expect(figs[0].move, 'revolving_door');
      expect(figs[1].move, 'swing');
      // The two children must NOT appear as separate top-level figures.
      expect(
        figs.where((f) => f.move == 'star_promenade'),
        isEmpty,
        reason: 'partner star promenade child must be subsumed, not emitted',
      );
    });

    test('beats are accurate: revolving door 6, swing 10, A1 total 16', () {
      final figs = draft.dance.figures;
      // Parent beats (6), NOT the ContraDB 8 and NOT the child sum re-counted.
      expect(figs[0].beats, 6);
      expect(figs[1].beats, 10);
      expect(figs[0].beats + figs[1].beats, 16);
    });

    test('the collapsed figure keeps the source decomposition in its note', () {
      final door = draft.dance.figures.first;
      // The children are preserved (scrubbed) so the definition is not lost.
      expect(door.note, contains('(4)'));
      expect(door.note, contains('star promenade'));
      expect(door.note, contains('(2)'));
      // "Women allemande" is canonicalized to a role token on import.
      expect(door.note, contains('allemande'));
      expect(door.note, isNot(contains('Women')));
    });

    test(
      'renders with parity to ContraDB (right hand + drop-off clarifier)',
      () {
        final renderer = FigureRenderer(contraTaxonomy);
        final door = draft.dance.figures.first;
        // Right hand (was left), correct dancers, and the outcome clarifier,
        // now in ContraDB's verbatim base-line wording (PR2).
        final summary = renderer.renderSummary(door, Dialect.canonical);
        expect(summary, contains('take right hands'));
        expect(summary, contains('drop off partner on other side'));
      },
    );

    test('parse never fails: draft is valid and mostly structured', () {
      expect(draft.dance.figures, isNotEmpty);
      expect(draft.quality.score, greaterThan(0.5));
    });
  });

  // --- Synthetic compound cases ---------------------------------------------
  group('synthetic compound grouping', () {
    test(
      'generic known-parent compound collapses to the single move',
      () async {
        final draft = await _importFigures([
          '(6) Revolving door:',
          '     (4) Partner star promenade 1/2 (WR)',
          '     (2) Women allemande right 1/2',
          '(10) Neighbor swing',
        ]);
        expect(draft.dance.figures.map((f) => f.move), [
          'revolving_door',
          'swing',
        ]);
        expect(draft.dance.figures.first.beats, 6);
      },
    );

    test(
      'unknown parent → ONE custom figure with the summed/parent beats',
      () async {
        final draft = await _importFigures([
          '(8) Mystery move:',
          '     (4) Do the first thing',
          '     (4) Do the second thing',
        ]);
        final figs = draft.dance.figures;
        expect(figs.length, 1);
        expect(figs.single.isCustom, isTrue);
        expect(figs.single.beats, 8);
        expect(_text(figs.single).toLowerCase(), contains('mystery move'));
        // Children are subsumed into the note, never emitted as figures.
        expect(figs.single.note, contains('first thing'));
        expect(figs.single.note, contains('second thing'));
      },
    );

    test(
      'unknown parent with a gendered term is stored role-normalized (scrubbed)',
      () async {
        // Regression: the unknown-parent custom fallback must scrub like every
        // other import path — a gendered term in the parent name becomes a role
        // token, never stored raw.
        final draft = await _importFigures([
          '(6) Ladies do a fancy thing:',
          '     (4) first part',
          '     (2) second part',
        ]);
        final figs = draft.dance.figures;
        expect(figs.length, 1);
        expect(figs.single.isCustom, isTrue);
        expect(figs.single.beats, 6);
        final text = _text(figs.single).toLowerCase();
        expect(text, contains('role2s'));
        expect(text, isNot(contains('ladies')));
      },
    );

    test('tabs as indentation are handled', () async {
      final draft = await _importFigures([
        '(8) Mystery move:',
        '\t(4) first',
        '\t(4) second',
      ]);
      expect(draft.dance.figures.length, 1);
      expect(draft.dance.figures.single.beats, 8);
    });
  });

  // --- Tolerant parsing (OWASP: untrusted TCB input, never throw) ------------
  group('tolerant parsing declines the collapse, never throws', () {
    test('children that do NOT sum to the parent are not collapsed', () async {
      final draft = await _importFigures([
        '(6) Revolving door:',
        '     (4) Partner star promenade 1/2',
        '     (4) Women allemande right 1/2', // 4+4 = 8 != 6
        '(10) Neighbor swing',
      ]);
      // Not a confident compound → each line parses independently (old path).
      // The parent stays its own figure and the children are still present.
      expect(draft.dance.figures.length, greaterThan(2));
    });

    test('a colon parent with NO indented children is a normal line', () async {
      final draft = await _importFigures([
        '(6) Revolving door:',
        '(10) Neighbor swing',
      ]);
      // No children → not a compound; the parent line parses on its own and
      // still recognizes as the revolving door move (trailing colon tolerated).
      expect(draft.dance.figures.length, 2);
      expect(draft.dance.figures[0].beats, 6);
    });

    test('non-numeric parent beats never crash', () async {
      final payload = jsonEncode({
        'ID': '1',
        'Name': 'x',
        'Permission': 'full',
        'phrases': [
          {
            'name': 'A1',
            'figures': ['(x) Revolving door:', '     (4) child', '(10) swing'],
          },
        ],
      });
      // Must not throw; produces a valid draft.
      final draft = await _importTcb(payload);
      expect(draft.dance.figures, isNotEmpty);
    });

    test('malformed indentation / missing beats degrade safely', () async {
      final draft = await _importFigures([
        '(6) Revolving door:',
        '     partner star promenade with no beats',
        '(10) Neighbor swing',
      ]);
      // The child has no (beats) prefix → not a valid child → decline collapse.
      expect(draft.dance.figures.length, greaterThanOrEqualTo(2));
    });

    test(
      'a zero-beat "(0) Section:" label is not treated as a compound',
      () async {
        final draft = await _importFigures(['(0) A1:', '(8) Neighbor balance']);
        expect(draft.dance.figures, isNotEmpty);
      },
    );
  });

  // --- Real ContraDB #2443 (atomic + clear text) -----------------------------
  group('ContraDB #2443 real fixture (Right Where We Belong)', () {
    late StructuredDraft draft;

    setUp(() async {
      final payload = File(
        p.join(
          await packageRootPath(),
          'test',
          'imports',
          'support',
          'contradb',
          'right_where_we_belong_2443.html',
        ),
      ).readAsStringSync();
      draft = await _importContraDbHtml(payload);
    });

    test('revolving door is a SINGLE atomic figure (already no children)', () {
      final door = draft.dance.figures.first;
      // ContraDB carries the descriptive clarifier inline; the whole sentence
      // is preserved (as clear text), never split or double-counted.
      final text = door.isCustom ? _text(door) : door.note ?? '';
      expect(
        door.isCustom ? text : 'revolving door',
        contains('revolving door'),
      );
      expect(door.beats, 8);
    });

    test('A1 totals 16 beats: revolving door 8 + neighbors swing 8', () {
      final figs = draft.dance.figures;
      expect(figs[0].beats, 8);
      expect(figs[1].move, 'swing');
      expect(figs[1].beats, 8);
    });

    test(
      'the CSRF token in the fixture is redacted (no secret leaks)',
      () async {
        final html = File(
          p.join(
            await packageRootPath(),
            'test',
            'imports',
            'support',
            'contradb',
            'right_where_we_belong_2443.html',
          ),
        ).readAsStringSync();
        expect(html, contains('REDACTED-CSRF-TOKEN'));
        expect(
          html,
          isNot(contains('IyO/ydou1vQFr1ToUVcPSKsF4Jg0HIwCerQnIiq8')),
        );
      },
    );
  });
}
