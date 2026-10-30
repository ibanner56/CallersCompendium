import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: a square through's balance. A balance the line states is kept;
/// otherwise the beats decide it (balance when beats >= 2 x places + 4).
/// Caller's Companion's `Partner R-hand balance, square through 2` is one
/// square through, and its comma pass lists are read.
void main() {
  group('balance from beats', () {
    final importers = {
      'free-text entry': (String line) async => parseFreeTextFigureEntry(line),
      "Caller's Companion": _ccFigures,
      "Caller's Box": (String line) => _tcbFigures([line]),
      're-parse': (String line) async => reparseImportGapFigures([
        customFigure(
          _lineText(line),
          beats: _lineBeats(line),
          origin: CustomOrigin.importGap,
        ),
      ]).figures,
    };
    for (final MapEntry(key: path, value: read) in importers.entries) {
      test('$path: enough beats for a balance', () async {
        for (final line in [
          '(8) Square through 2',
          '(10) Square through 3',
          '(12) Square through 4',
          '(16) Square through 2',
        ]) {
          final f = (await read(line)).single;
          expect(f.move, 'square_through', reason: line);
          expect(f.params['balance'], isTrue, reason: line);
        }
      });

      test('$path: too few beats for a balance', () async {
        for (final line in [
          '(4) Square through 2',
          '(8) Square through 3',
          '(8) Square through 4',
        ]) {
          final f = (await read(line)).single;
          expect(f.move, 'square_through', reason: line);
          expect(f.params['balance'], isFalse, reason: line);
        }
      });

      test('$path: a stated balance holds against the beats', () async {
        final f = (await read(
          '(4) Partner R-hand balance, square through 2',
        )).single;
        expect(f.move, 'square_through');
        expect(f.params['balance'], isTrue);
      });

      test('$path: "without hands" stays without a balance', () async {
        final f = (await read('(16) Square through 2 without hands')).single;
        expect(f.move, 'square_through');
        expect(f.params['balance'], isFalse);
      });
    }

    test('a comma pass list leaves the balance to the beats', () async {
      // Unlike a Caller's Box `;` list, it says nothing about the balance, so
      // where no beat rule runs it reads like a square through with no list.
      final bare = parseFigureLinesFanOut(
        'Square through 2 (PR, NL)',
        beats: 8,
      ).single;
      expect(bare.params['who'], 'partners');
      expect(bare.params.containsKey('balance'), isFalse);

      final imported = (await _ccFigures(
        '(8) Square through 2 (PR, NL)',
      )).single;
      expect(imported.params['balance'], isTrue);
    });

    test("a Caller's Box pass list gets the balance its beats imply", () async {
      // The decoder writes `balance: false`; the beat rule replaces it on a
      // standalone line, as it applies to The Caller's Box too.
      final balanced = (await _tcbFigures([
        '(8) Square through 2 (PR;N2L)',
      ])).single;
      expect(balanced.params['who'], 'partners');
      expect(balanced.params['balance'], isTrue);

      final bare = (await _tcbFigures([
        '(4) Square through 2 (PR;N2L)',
      ])).single;
      expect(bare.params['balance'], isFalse);
    });

    test("a Caller's Box compound keeps folding its balance child", () async {
      // Maintainer decision: inside a compound the beat rule does not run. The
      // 8-beat child is long enough for its own balance, so it would keep the
      // balance child out if the rule ran on it.
      final f = (await _tcbFigures([
        '(12) Interrupted square through 2 [with N2, partner]:',
        '     (4) Partner balance (RH)',
        '     (8) Square through 2 (PR;N2L)',
      ])).single;
      expect(f.move, 'square_through');
      expect(f.params['balance'], isTrue);
      expect(f.params['beats'], 12);
    });

    test("a Caller's Box balance line still folds in", () async {
      // The rule runs after the cross-line merge, so a square through long
      // enough for its own balance still takes the balance line before it, as
      // it did before #1975.
      for (final (line, beats) in [
        ('(8) Square through 2 (PR;N2L)', 12),
        ('(12) Square through 4 (PR;NL;PR;NL)', 16),
      ]) {
        final f = (await _tcbFigures([
          '(4) Partner balance (RH)',
          line,
        ])).single;
        expect(f.move, 'square_through', reason: line);
        expect(f.params['balance'], isTrue, reason: line);
        expect(f.params['beats'], beats, reason: line);
      }
    });

    test('a split line\'s beats are not the square through\'s own', () async {
      final figures = await _ccFigures('(8) Square through 3; Neighbor swing');
      expect(figures.map((f) => f.move), ['square_through', 'swing']);
      expect(figures.first.params.containsKey('balance'), isFalse);
    });

    test('a Caller\'s Box `;` line read as one figure and a note', () async {
      // The line's total stays on the one figure, but some of it is the
      // noted clause's.
      final f = (await _tcbFigures(['(8) Square through 2; face up'])).single;
      expect(f.move, 'square_through');
      expect(f.note, 'face up');
      expect(f.params.containsKey('balance'), isFalse);
    });
  });

  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry('(8) $line'),
  };
  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure single(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        return figures.single;
      }

      test('a stated balance is one balanced square through', () {
        // Maintainer decision on #1975: the pair that balances is the first
        // pull, and the balance's hand is the square through's.
        for (final (line, who, places) in [
          ('Partner R-hand balance, square through 2', 'partners', 2),
          ('Partner Right-hand balance, square through two', 'partners', 2),
          (
            'Neighbor Right-hand balance and square through two',
            'neighbors',
            2,
          ),
          ('Partner right hand balance, square through 4', 'partners', 4),
          ('Neighbor L-hand balance, square through three', 'neighbors', 3),
        ]) {
          final f = single(line);
          expect(f.move, 'square_through', reason: line);
          expect(f.params['who'], who, reason: line);
          expect(f.params['places'], places, reason: line);
          expect(f.params['balance'], isTrue, reason: line);
          expect(
            f.params['hand'],
            line.contains(' L-') ? 'left' : 'right',
            reason: line,
          );
          expect(f.note, isNull, reason: line);
        }
      });

      test('a pass list that agrees gives who2', () {
        for (final (line, who2) in [
          (
            'Partner Right-hand balance, square through 2 (PR, N2L)',
            'nextNeighbors',
          ),
          (
            'Partner Right-hand balance, square through 2 (P R, N1 L)',
            'neighbors',
          ),
          (
            'Neighbor Right-hand balance, square through two (Neighbor R, Partner L)',
            'partners',
          ),
        ]) {
          final f = single(line);
          expect(f.params['who2'], who2, reason: line);
          expect(f.note, isNull, reason: line);
        }
      });

      test('a pass list that disagrees or does not decode is the note', () {
        for (final (line, note) in [
          // Neighbors first, but the partners balance.
          ('Partner R-hand balance, square through 2 (NR, PL)', 'NR, PL'),
          // The hand differs.
          ('Partner R-hand balance, square through 2 (PL, NR)', 'PL, NR'),
          // Phantoms have no dancer set.
          (
            'Partner R-hand balance, square through 2 (Ph1R, Ph2L)',
            'Ph1R, Ph2L',
          ),
        ]) {
          final f = single(line);
          expect(f.move, 'square_through', reason: line);
          expect(f.params['who'], 'partners', reason: line);
          expect(f.params.containsKey('who2'), isFalse, reason: line);
          expect(f.note, note, reason: line);
        }
      });

      test('where it ends is the note', () {
        for (final (line, note) in [
          (
            'Partner R-Hand balance, square through 2, to New Neighbors',
            'to New Neighbors',
          ),
          (
            'Partner right hand balance, square through two (to new Neighbor)',
            'to new Neighbor',
          ),
        ]) {
          final f = single(line);
          expect(f.move, 'square_through', reason: line);
          expect(f.note, note, reason: line);
        }
      });

      test('anything else keeps the line text', () {
        for (final line in [
          'Partner R-hand balance, square through 2, then swing',
          'Partner R-hand balance, square through 2 and swing',
          'Partner R-hand balance, square through 2, to new neighbors and swing',
          'Partner R-hand balance, square through 2 to the end then balance',
          'Wave R-hand balance, square through 2',
          'Partner R-hand balance, square through five',
        ]) {
          expect(read(line).single.isCustom, isTrue, reason: line);
        }
      });

      test("a comma pass list on a square through with hands is read", () {
        final f = single('Square through 3 (NL, PR, NL)');
        expect(f.move, 'square_through');
        expect(f.params['who'], 'neighbors');
        expect(f.params['who2'], 'partners');
        expect(f.params['hand'], 'left');
      });

      test('a comma pass list that does not decode is kept as the note', () {
        // An all-capitals list was dropped before (#1975); one with a
        // lowercase letter was already kept by the prose-note reader. These
        // hands do not alternate.
        final f = single('Square through 2 (NR, PR)');
        expect(f.move, 'square_through');
        expect(f.params.containsKey('who'), isFalse);
        expect(f.note, 'NR, PR');
      });
    });
  }
}

final RegExp _beatsPrefix = RegExp(r'^\((\d+)\)\s*');

int _lineBeats(String line) =>
    int.parse(_beatsPrefix.firstMatch(line)!.group(1)!);

String _lineText(String line) => line.replaceFirst(_beatsPrefix, '');

/// The figures a Caller's Companion text export imports for one body line.
Future<List<Figure>> _ccFigures(String line) async {
  final adapter = CallersCompanionTextAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: 'Test Dance\nType: Contra\n\nA1   $line\n'),
  );
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return _figures(draft.dance);
}

/// The figures a Caller's Box record imports for one phrase's lines.
Future<List<Figure>> _tcbFigures(List<String> lines) async {
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(
    ImportRequest(
      payload: jsonEncode({
        'ID': '42',
        'Name': 'Test Dance',
        'Permission': 'full',
        'phrases': [
          {'name': 'A1', 'figures': lines},
        ],
      }),
    ),
  );
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return _figures(draft.dance);
}

List<Figure> _figures(Dance dance) => switch (dance.figuresSource) {
  DecodedFigures(:final figures) => figures,
  UnreadableFigures() => throw StateError('figures did not decode'),
};
