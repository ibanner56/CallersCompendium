import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

/// Every figure should read back from its own displayed text (#2121): typing or
/// pasting the line the app shows for a figure should give back that figure.
///
/// The sweep renders every shipped move (not `custom`) at its defaults, then
/// once per value of each choice, direction, side, spin, fraction, flag and
/// dancer parameter, each value set alone on an otherwise default figure
/// ([_sweep]). Each figure is rendered with [FigureRenderer.renderSummary] in
/// every shipped dialect preset, the text is read with
/// [parseFreeTextFigureEntry] in that dialect, and the result is rendered
/// again. A figure passes only when it reads back as exactly one figure of the
/// same move whose rendering is the same text. Comparing renderings, not
/// params, allows for details the display hides on purpose, such as a
/// balance's hand.
///
/// [_knownFailuresPath] lists the figures that do not read back yet, so the
/// count can only go down:
///
/// * A figure that fails and is not listed fails this test. Fix the reading;
///   if a new move or param value cannot be read yet, adding its lines by hand
///   is a decision to state in the PR, since it raises the count.
/// * A listed figure that now reads back fails this test too, so the list
///   cannot go stale. Run with `UPDATE_ROUND_TRIP=1` to drop the lines that
///   pass. That never adds a line.
const _knownFailuresPath =
    'test/imports/fixtures/figure_round_trip_known_failures.txt';

/// One figure for each of [contraTaxonomy]'s moves at its defaults, then one
/// per value of each param a closed domain can enumerate (beats, rotations,
/// places and free text are left at their defaults).
List<Figure> _sweep() => [
  for (final move in contraTaxonomy.moves.values)
    if (move.id != customMove) ...[
      testFigure(move: move.id),
      for (final MapEntry(key: name, value: spec) in move.params.entries)
        for (final value in _domain(spec))
          testFigure(move: move.id, params: {name: value}),
    ],
];

List<Object?> _domain(ParamSpec spec) => switch (spec.kind) {
  ParamKind.choice => spec.choices ?? const [],
  ParamKind.direction => spec.choices ?? ParamVocab.directions,
  ParamKind.handedness ||
  ParamKind.shoulder => spec.choices ?? ParamVocab.sides,
  ParamKind.spinDirection => spec.choices ?? ParamVocab.spins,
  ParamKind.fraction => spec.choices ?? ParamVocab.fractions,
  ParamKind.flag => const [true, false],
  ParamKind.dancerSet ||
  ParamKind.dancerPair => spec.choices ?? ParamVocab.dancerSets,
  ParamKind.rotation ||
  ParamKind.places ||
  ParamKind.number ||
  ParamKind.beats ||
  ParamKind.text => const [],
};

/// A figure's line in the known-failures list: the dialect, the move, the
/// params set on it, and the text it displays as, tab-separated.
String _key(Dialect dialect, Figure figure, String text) =>
    [dialect.name, figure.move, jsonEncode(figure.params), text].join('\t');

/// Why [figure], displayed as [text] in [dialect], does not read back, or
/// `null` when it does.
String? _failure(
  FigureRenderer renderer,
  Dialect dialect,
  Figure figure,
  String text,
) {
  final read = parseFreeTextFigureEntry(text, dialect: dialect);
  final back = [for (final f in read) renderer.renderSummary(f, dialect)];
  if (read.length == 1 && read.single.move == figure.move) {
    return back.single == text ? null : 'reads back as "${back.single}"';
  }
  return 'reads as ${read.map((f) => f.move).toList()}: "${back.join(' | ')}"';
}

void main() {
  group('a subject before the balance reads back (#2121)', () {
    final renderer = FigureRenderer(contraTaxonomy);
    final cases = [
      testFigure(move: 'box_the_gnat', params: {'balance': true}),
      testFigure(
        move: 'box_the_gnat',
        params: {'who': 'role2s', 'balance': true},
      ),
      testFigure(move: 'swat_the_flea', params: {'balance': true}),
      for (final who in ['role1s', 'role2s', 'centers', 'ones', 'twos'])
        for (final slide in ['left', 'right'])
          testFigure(
            move: 'rory_o_more',
            params: {'who': who, 'slide': slide, 'balance': true},
          ),
    ];
    for (final dialect in Dialect.presets) {
      for (final figure in cases) {
        final text = renderer.renderSummary(figure, dialect);
        test('${dialect.name}: $text', () {
          // The display puts the subject first: `larks balance & Rory O'More`.
          expect(text, contains(' balance & '));
          final read = parseFreeTextFigureEntry(text, dialect: dialect);
          expect(read, hasLength(1));
          expect(read.single.move, figure.move);
          for (final MapEntry(:key, :value) in figure.params.entries) {
            expect(read.single.params[key], value, reason: key);
          }
        });
      }
    }
  });

  test('a box read with its balance is 8 beats unless the line says', () {
    Figure read(String line) => parseFreeTextFigureEntry(line).single;
    expect(read('neighbor balance & box the gnat').params['beats'], 8);
    expect(read('(16) neighbor balance & box the gnat').params['beats'], 16);
    expect(read('neighbor box the gnat').params, isNot(contains('beats')));
  });

  test('a balanced box in a later clause adds no beats to the line', () {
    // A later clause is read beats-absent: 8 beats on it would be counted on
    // top of the line's 24.
    final figures = parseFreeTextFigureEntry(
      '(24) partner swing; neighbor balance & box the gnat',
    );
    expect(figures.map((f) => f.move), ['swing', 'box_the_gnat']);
    expect(figures.first.params['beats'], 24);
    expect(figures.last.params['balance'], isTrue);
    expect(figures.last.params, isNot(contains('beats')));
  });

  test('so does one beside a shorthand, read clause by clause', () {
    final shorthands = ShorthandMappings([
      ShorthandMapping(
        token: 'pbs',
        figures: [
          testFigure(move: 'swing', params: const {'who': 'partners'}),
        ],
      ),
    ]);
    final figures = parseFreeTextFigureEntry(
      '(24) pbs; neighbor balance & box the gnat',
      shorthands: shorthands,
    );
    expect(figures.map((f) => f.move), ['swing', 'box_the_gnat']);
    expect(figures.first.params['beats'], 24);
    expect(figures.last.params['balance'], isTrue);
    expect(figures.last.params, isNot(contains('beats')));
  });

  test('every figure reads back from its displayed text, or is listed', () async {
    final renderer = FigureRenderer(contraTaxonomy);
    final figures = _sweep();
    // Guards the sweep itself: an empty or shrunken sweep would pass vacuously.
    expect(figures.length, greaterThan(1500), reason: 'the sweep shrank');

    final failures = <String, String>{};
    for (final dialect in Dialect.presets) {
      for (final figure in figures) {
        final text = renderer.renderSummary(figure, dialect);
        final why = _failure(renderer, dialect, figure, text);
        if (why != null) failures[_key(dialect, figure, text)] = why;
      }
    }

    final file = File(p.join(await packageRootPath(), _knownFailuresPath));
    final lines = file.readAsLinesSync();
    final known = [
      for (final line in lines)
        if (line.isNotEmpty && !line.startsWith('#')) line,
    ];
    expect(known.toSet(), hasLength(known.length), reason: 'duplicate lines');

    final added = [
      for (final key in failures.keys)
        if (!known.contains(key)) '$key\n    ${failures[key]}',
    ];
    final fixed = [
      for (final key in known)
        if (!failures.containsKey(key)) key,
    ];
    if (fixed.isNotEmpty && Platform.environment['UPDATE_ROUND_TRIP'] == '1') {
      final kept = [
        for (final line in lines)
          if (!fixed.contains(line)) line,
      ];
      file.writeAsStringSync('${kept.join('\n')}\n');
      fixed.clear();
    }
    expect(
      added,
      isEmpty,
      reason:
          '${added.length} figure(s) no longer read back from their own '
          'text:\n${added.take(30).join('\n')}',
    );
    expect(
      fixed,
      isEmpty,
      reason:
          '${fixed.length} listed figure(s) now read back; run with '
          'UPDATE_ROUND_TRIP=1 to drop them from $_knownFailuresPath:\n'
          '${fixed.take(30).join('\n')}',
    );
  });
}
