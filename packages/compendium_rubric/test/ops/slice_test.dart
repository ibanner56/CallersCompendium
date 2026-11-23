import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op passed: $result');
  return (result as Err<Formation, OpError>).error;
}

Formation progressing(Operation op, Formation input) {
  final result = OperationInvocation(op, progression: true).apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  // The canonical two-hands-four Becket start the slide's worked examples use.
  final becketStart = startingFormation(FormationType.becketCw, handsFour: 2);

  group('slice lands like a slide along the set (user-ruled 2026-11-22)', () {
    for (final dir in SlideDirection.values) {
      test('slice ${dir.key}, straight back, is one slide ${dir.key}', () {
        final sliced = applyOk(Slice(slice: dir), becketStart);
        final slid = applyOk(SlideAlongSet(slide: dir), becketStart);
        expect(sliced.toRolesNotation(), slid.toRolesNotation());
        expect(sliced, slid);
        // And it really moved someone, so the comparison is not vacuous.
        expect(sliced.toRolesNotation(), isNot(becketStart.toRolesNotation()));
      });

      test('slice ${dir.key}, back on the diagonal, is two slides', () {
        final sliced = applyOk(
          Slice(slice: dir, back: SliceReturn.diagonal),
          becketStart,
        );
        final once = applyOk(SlideAlongSet(slide: dir), becketStart);
        final twice = applyOk(SlideAlongSet(slide: dir), once);
        expect(sliced, twice);
        expect(sliced.toRolesNotation(), isNot(once.toRolesNotation()));
      });

      test('flagged as the progression, slice ${dir.key} is its own', () {
        expect(
          progressing(Slice(slice: dir), becketStart),
          progressing(SlideAlongSet(slide: dir), becketStart),
        );
      });
    }
  });

  group('a flagged double slice is two progressions (user-ruled 2026-11-23)', () {
    // "Diagonal is double, straight back is single": a diagonal return is two
    // slides, and as the progression it is both of a double progression.
    Map<String, Object?> record(
      List<Map<String, Object?>> figures, {
      String progression = 'double',
    }) => {
      'title': 'double slice',
      'formation': {'shape': 'becket'},
      'progression': progression,
      'figures': figures,
    };
    Map<String, Object?> flagged(String move, [Map<String, Object?>? params]) =>
        {
          'move': move,
          'params': params ?? <String, Object?>{},
          'progression': true,
        };
    CompileResult compiled(Map<String, Object?> raw) {
      final parsed = parseDance(raw);
      expect(parsed, isA<Ok<Dance, DanceParseError>>(), reason: '$parsed');
      return compile((parsed as Ok<Dance, DanceParseError>).value);
    }

    for (final dir in SlideDirection.values) {
      test(
        'slice ${dir.key} on the diagonal, flagged, is two flagged slides',
        () {
          final start = startingFormation(FormationType.becketCw, handsFour: 3);
          final once = progressing(SlideAlongSet(slide: dir), start);
          expect(
            progressing(Slice(slice: dir, back: SliceReturn.diagonal), start),
            progressing(SlideAlongSet(slide: dir), once),
          );
        },
      );
    }

    test('a double-progression dance compiles on one flagged double slice', () {
      // Positive control first: the same dance written as two flagged slides.
      expect(
        compiled(
          record([flagged('slide_along_set'), flagged('slide_along_set')]),
        ),
        isA<Compiled>(),
      );
      expect(
        compiled(
          record([
            flagged('slice', {'return': 'diagonal'}),
          ]),
        ),
        isA<Compiled>(),
      );
    });

    test('and it is not a single progression', () {
      expect(
        compiled(
          record([
            flagged('slice', {'return': 'diagonal'}),
          ], progression: 'single'),
        ),
        isNot(isA<Compiled>()),
      );
    });
  });

  group('slice deferrals refuse rather than approximate', () {
    test('by a single dancer', () {
      final error = applyErr(const Slice(by: SliceBy.dancer), becketStart);
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('with no return', () {
      final error = applyErr(const Slice(back: SliceReturn.none), becketStart);
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('a dancer standing in a centre column, as the slide does', () {
      // A line of four: the slide has no side lines to move. Checked against
      // the preconditions directly, because `apply` settles wave offsets first.
      final line = parseRolesNotation(const [
        '. R1-A . L1-A .',
        '. L2-B . R2-B .',
      ], type: FormationType.becketCw);
      final error = const Slice().checkPreconditions(line);
      expect(error, isNotNull);
      expect(error!.kind, ErrorKind.unresolvableDancerSet);
      expect(error.kind, const SlideAlongSet().checkPreconditions(line)!.kind);
    });
  });

  group('slice metadata', () {
    test('is progression-eligible and is its own progression', () {
      expect(const Slice().progressionEligible, isTrue);
      expect(const Slice().isItsOwnProgression, isTrue);
    });

    test('reaches one grouping per slide', () {
      expect(const Slice().hands4Contribution, 1);
      expect(const Slice(back: SliceReturn.diagonal).hands4Contribution, 2);
    });
  });
}
