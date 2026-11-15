import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A titled container renders as `"<title> - <the same container untitled>"`
/// on every render path, canonical included, and exactly once: a nested
/// container's own title opens its own part of the line and nothing else.
void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final dialect = Dialect.larksRobins;

  final allemande = Figure(
    move: 'allemande',
    params: const {'who': 'role1s', 'hand': 'right', 'travel': 0.5, 'beats': 4},
  );
  final starPromenade = Figure(
    move: 'star_promenade',
    params: const {'who': 'role1s', 'travel': 0.5, 'beats': 4},
  );
  final orbit = Figure(
    move: 'orbit',
    params: const {'who': 'role2s', 'direction': 'clockwise', 'travel': 0.5},
  );
  final balance = Figure(
    move: 'balance',
    params: const {'who': 'partners', 'beats': 4},
  );

  Figure build(String kind, {String? title, String? wordingOverride}) =>
      switch (kind) {
        meanwhileMove => Figure.meanwhile(
          figures: [allemande, orbit],
          beats: 8,
          title: title,
          wordingOverride: wordingOverride,
        ),
        modifierMove => Figure.modifier(
          figures: [allemande, orbit],
          beats: 8,
          title: title,
          wordingOverride: wordingOverride,
        ),
        _ => Figure.sequence(
          figures: [allemande, starPromenade],
          beats: 8,
          title: title,
          wordingOverride: wordingOverride,
        ),
      };

  final renders = <String, String Function(Figure)>{
    'render': (f) => renderer.render(f, dialect),
    'render with decimals': (f) => renderer.render(f, dialect, decimals: true),
    'renderVerbose': (f) => renderer.renderVerbose(f, dialect),
    'renderSummary': (f) => renderer.renderSummary(f, dialect),
    'renderSummary verbose': (f) =>
        renderer.renderSummary(f, dialect, verbose: true),
    'renderSummaryWithCanonicalDiscouragedTerms': (f) =>
        renderer.renderSummaryWithCanonicalDiscouragedTerms(f, dialect),
    'renderCanonical': renderer.renderCanonical,
  };

  for (final kind in containerMoves) {
    group('a titled $kind', () {
      final untitled = build(kind);
      final titled = build(kind, title: 'Flutterwheel');
      for (final MapEntry(key: name, value: renderOf) in renders.entries) {
        test('$name opens with the title, once', () {
          expect(renderOf(titled), 'Flutterwheel - ${renderOf(untitled)}');
        });
      }

      test('its wording override still follows the title', () {
        final overridden = build(
          kind,
          title: 'Flutterwheel',
          wordingOverride: 'role1s turn the role2s across',
        );
        expect(
          renderer.render(overridden, dialect),
          'Flutterwheel - larks turn the robins across',
        );
        expect(
          renderer.renderSummary(overridden, dialect),
          'Flutterwheel - larks turn the robins across',
        );
        // The override is display-only; canonical keeps the structural line.
        expect(
          renderer.renderCanonical(overridden),
          'Flutterwheel - ${renderer.renderCanonical(untitled)}',
        );
      });
    });
  }

  test('role words in a title follow the dialect, and stay canonical tokens '
      'in the canonical line', () {
    final titled = build(sequenceMove, title: 'role1s flutterwheel');
    expect(
      renderer.render(titled, dialect),
      startsWith('larks flutterwheel - '),
    );
    expect(
      renderer.render(titled, Dialect.leadsFollows),
      startsWith('leads flutterwheel - '),
    );
    expect(
      renderer.renderCanonical(titled),
      startsWith('role1s flutterwheel - '),
    );
  });

  group('a titled container inside another', () {
    test('a titled sequence that is one side of a meanwhile titles only its '
        'side', () {
      final inner = Figure.sequence(
        figures: [allemande, starPromenade],
        beats: 8,
        title: 'Flutterwheel',
      );
      final outer = Figure.meanwhile(figures: [inner, orbit], beats: 8);
      final innerUntitled = Figure.sequence(
        figures: [allemande, starPromenade],
        beats: 8,
      );
      final untitledOuter = Figure.meanwhile(
        figures: [innerUntitled, orbit],
        beats: 8,
      );
      for (final MapEntry(key: name, value: renderOf) in renders.entries) {
        final expected = renderOf(untitledOuter).replaceFirst(
          renderOf(innerUntitled),
          'Flutterwheel - ${renderOf(innerUntitled)}',
        );
        expect(renderOf(outer), expected, reason: name);
        expect(
          'Flutterwheel'.allMatches(renderOf(outer)).length,
          1,
          reason: name,
        );
      }
    });

    test('a titled meanwhile and a titled sequence as a modifier\'s parts '
        'each carry their own title', () {
      final titledSides = Figure.meanwhile(
        figures: [allemande, orbit],
        beats: 8,
        title: 'Ricochet',
      );
      final titledRun = Figure.sequence(
        figures: [allemande, starPromenade],
        beats: 8,
        title: 'Flutterwheel',
      );
      for (final part in [titledSides, titledRun]) {
        final modifier = Figure.modifier(figures: [balance, part], beats: 8);
        final title = part.containerTitle!;
        final untitledPart = part.copyWith(
          params: {...part.params}..remove(containerTitleKey),
        );
        final untitledModifier = Figure.modifier(
          figures: [balance, untitledPart],
          beats: 8,
        );
        for (final MapEntry(key: name, value: renderOf) in renders.entries) {
          final line = renderOf(modifier);
          expect(title.allMatches(line).length, 1, reason: '$name: $line');
          expect(
            line.replaceFirst('$title - ', ''),
            renderOf(untitledModifier),
            reason: name,
          );
        }
        // And as the core, which renders through the summary path.
        final asCore = Figure.modifier(figures: [part, balance], beats: 8);
        expect(renderer.render(asCore, dialect), startsWith('$title - '));
      }
    });
  });

  test('an ordinary figure never reads a "title" param as a title', () {
    // invalid-fixture: a stray title param on an ordinary figure, on purpose
    final custom = Figure(
      move: customMove,
      params: const {'text': 'do the thing', containerTitleKey: 'Nope'},
    );
    // invalid-fixture: a stray title param on an ordinary figure, on purpose
    final move = Figure(
      move: 'balance',
      params: const {'who': 'partners', containerTitleKey: 'Nope'},
    );
    expect(custom.containerTitle, isNull);
    expect(move.containerTitle, isNull);
    for (final renderOf in renders.values) {
      expect(renderOf(custom), isNot(contains('Nope')));
      expect(renderOf(move), isNot(contains('Nope')));
    }
  });
}
