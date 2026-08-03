@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:compendium_core/testing.dart';

import '../../tool/check_fixture_validity.dart';

/// Unit tests for the figure-fixture validity ratchet.
///
/// The checker was previously covered only by falsification against the real
/// tree — enough to show it fires, but not enough to pin *which* constructions
/// it treats as fixtures. A review of PR #789 raised two claims about that
/// dispatch (that `Figure.meanwhile(...)` would be misread as a fixture, and
/// that the `switch` in `_parse` fell through from `move` into `params`). Both
/// were incorrect, but settling them needed hand-built probes — which is
/// exactly the gap these tests close: the dispatch rules are now executable
/// rather than argued.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fixture_ratchet'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Runs the checker over a synthetic `app/test` tree containing [source].
  List<FixtureViolation> check(String source) {
    final testDir = Directory('${tmp.path}/app/test')
      ..createSync(recursive: true);
    File('${testDir.path}/sample_test.dart').writeAsStringSync(source);
    return analyse(testFiles(tmp), tmp.path).violations;
  }

  group('literal fixtures', () {
    test('a valid fixture passes', () {
      expect(
        check("f() { Figure(move: 'swing', params: {'who': 'partners'}); }"),
        isEmpty,
      );
    });

    test('an out-of-domain value is reported', () {
      final v = check(
        "f() { Figure(move: 'swing', params: {'who': 'partner'}); }",
      );
      expect(v, hasLength(1));
      expect(v.single.kind, 'invalid_param_value');
    });

    test('an unknown move is reported', () {
      expect(
        check("f() { Figure(move: 'not_a_move'); }").single.kind,
        'unknown_move',
      );
    });

    test('a move and its params are BOTH read', () {
      // Pins that `_parse`'s switch does not fall through from `move` into
      // `params`: if it did, the `params:` branch would reject the string
      // `move:` argument and classify every literal fixture as dynamic, so
      // this out-of-domain value would surface as `unchecked-dynamic`
      // instead of `invalid_param_value`.
      final v = check(
        "f() { Figure(move: 'swing', params: {'who': 'nope'}); }",
      );
      expect(v.single.kind, 'invalid_param_value');
      expect(v.single.detail, contains('swing.who'));
    });
  });

  group('which constructions count as a fixture', () {
    test('a named constructor is not a fixture', () {
      // `Figure.meanwhile(...)` is a container, not a taxonomy figure, and has
      // no `move`/`params` to validate. Unresolved, the parser reports it as a
      // MethodInvocation named `meanwhile` (target `Figure`), so the
      // `Figure`-named visitor never sees it. Live in the suites today, e.g.
      // app/test/perform_card_meanwhile_test.dart.
      expect(
        check('f() { Figure.meanwhile(figures: [a, b], beats: 8); }'),
        isEmpty,
      );
    });

    test('an unrelated call ending in Figure is not a fixture', () {
      expect(check("f() { customFigure('text'); }"), isEmpty);
    });

    test('an explicit `new` IS a fixture', () {
      expect(
        check("f() { new Figure(move: 'not_a_move'); }").single.kind,
        'unknown_move',
      );
    });

    test('`new` with a named constructor is not a fixture', () {
      // Without resolution the parser cannot tell a named constructor from a
      // prefixed type, so it reports `Figure.meanwhile` as type `meanwhile`
      // with import prefix `Figure` — which fails the `Figure` type check and
      // is correctly ignored.
      expect(check('f() { new Figure.meanwhile(figures: [a]); }'), isEmpty);
    });
  });

  group('dynamic fixtures', () {
    test('a variable move is reported as unchecked', () {
      expect(
        check('f(String id) { Figure(move: id); }').single.kind,
        'unchecked-dynamic',
      );
    });

    test('a variable param value is reported as unchecked', () {
      expect(
        check(
          "f(String w) { Figure(move: 'swing', params: {'who': w}); }",
        ).single.kind,
        'unchecked-dynamic',
      );
    });
  });

  group('the invalid-fixture marker', () {
    test('both opt-out routes demand the same reason length', () {
      // A fixture can be waived two ways — this marker, and
      // `invalidTestFigure`'s `reason`. Two independent constants would let
      // one be relaxed while the other was not, which is the shape of every
      // hole found in this mechanism: a second route to the opt-out, gated
      // separately. Pinned as identity, not equality of two numbers, so the
      // alias cannot be replaced by a matching literal that later drifts.
      expect(minReasonLength, same(minFixtureReasonLength));
    });

    test('a substantive reason suppresses the violation', () {
      expect(
        check(
          'f() {\n'
          '  // invalid-fixture: deliberately out of domain to test the guard\n'
          "  Figure(move: 'swing', params: {'who': 'partner'});\n"
          '}',
        ),
        isEmpty,
      );
    });

    test('a too-short reason is a violation, and fails closed', () {
      // Both granularities fail closed: a rejected marker does not waive its
      // fixture, so the fixture is still checked and reports separately.
      // Anything else would let the laziest possible reason buy exactly the
      // suppression the reason requirement exists to deny.
      final v = check(
        'f() {\n'
        '  // invalid-fixture: n/a\n'
        "  Figure(move: 'swing', params: {'who': 'partner'});\n"
        '}',
      );
      expect(v.map((e) => e.kind), contains('weak-marker'));
      expect(
        v.map((e) => e.kind),
        contains('invalid_param_value'),
        reason: 'the fixture must stay checked, not be waived by a weak marker',
      );
    });

    test('a marker applies to a WRAPPED statement', () {
      // `dart format` wraps a long statement so the `Figure(` token lands on a
      // different line from the statement it belongs to. Looking only above
      // the token finds `final x =` — a non-comment line — and gives up, so
      // the marker silently stops working. Found in review; the formatter
      // produces this shape routinely, including elsewhere in this PR.
      expect(
        check(
          'f() {\n'
          '  // invalid-fixture: a substantive reason for this fixture\n'
          '  final x =\n'
          "      Figure(move: 'swing', params: {'who': 'partner'});\n"
          '}',
        ),
        isEmpty,
      );
    });

    test('a marker applies to a fixture nested in a wrapped call', () {
      expect(
        check(
          'f() {\n'
          '  // invalid-fixture: a substantive reason for this fixture\n'
          '  expect(\n'
          "    render(Figure(move: 'swing', params: {'who': 'partner'})),\n"
          "    'x',\n"
          '  );\n'
          '}',
        ),
        isEmpty,
      );
    });

    test('a weak reason on a wrapped statement is still caught', () {
      // The statement-level lookup must not become a second, ungated route
      // into suppression — the whole defect class on this PR.
      final v = check(
        'f() {\n'
        '  // invalid-fixture: n/a\n'
        '  final x =\n'
        "      Figure(move: 'swing', params: {'who': 'partner'});\n"
        '}',
      );
      expect(v.map((e) => e.kind), contains('weak-marker'));
    });

    test('a marker above unrelated code does not carry down', () {
      // The marker must introduce its own statement; a non-comment line
      // between it and the fixture ends its reach.
      final v = check(
        'f() {\n'
        '  // invalid-fixture: this marker belongs to the statement below it\n'
        '  final x = 1;\n'
        "  Figure(move: 'swing', params: {'who': 'partner'});\n"
        '}',
      );
      expect(v.single.kind, 'invalid_param_value');
    });

    test('a marker on an enclosing test covers fixtures inside it', () {
      expect(
        check(
          'void main() {\n'
          '  // invalid-fixture: the whole test is about out-of-domain input\n'
          "  test('x', () {\n"
          "    Figure(move: 'swing', params: {'who': 'partner'});\n"
          "    Figure(move: 'swing', params: {'who': 'neighbor'});\n"
          '  });\n'
          '}',
        ),
        isEmpty,
      );
    });
    test(
      'a weak reason on an enclosing test is reported, and fails closed',
      () {
        // A scope marker waives EVERY fixture inside it, so it is held to the
        // same standard as a per-fixture one. It must also fail closed: the
        // scope is not registered, so the fixtures it would have covered stay
        // checked rather than being waived by a marker that never justified
        // itself. Found in review of this PR — the scope path previously only
        // asked whether a marker existed, discarding its reason.
        final v = check(
          'void main() {\n'
          '  // invalid-fixture: n/a\n'
          "  test('x', () {\n"
          "    Figure(move: 'swing', params: {'who': 'partner'});\n"
          '  });\n'
          '}',
        );
        expect(v.map((e) => e.kind), contains('weak-marker'));
        expect(
          v.map((e) => e.kind),
          contains('invalid_param_value'),
          reason:
              'the fixture must stay checked, not be waived by a weak marker',
        );
      },
    );

    test('a weak reason on an enclosing group is reported too', () {
      final v = check(
        'void main() {\n'
        '  // invalid-fixture: todo\n'
        "  group('g', () {\n"
        "    Figure(move: 'swing', params: {'who': 'partner'});\n"
        '  });\n'
        '}',
      );
      expect(v.map((e) => e.kind), contains('weak-marker'));
    });
  });
}
