import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1971: a line that states an amount is never saved as a structured figure
/// with a different amount. Lines from a beta tester's Caller's Companion
/// library, as the `.USR` import hands them to the fan-out (beat prefix
/// removed).
void main() {
  Figure single(String line) {
    final figures = parseFigureLinesFanOut(line, beats: 8);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  void expectReads(
    String line,
    String move,
    Map<String, Object?> params, {
    String? note,
  }) {
    final f = single(line);
    expect(f.move, move, reason: line);
    for (final e in params.entries) {
      expect(f.params[e.key], e.value, reason: '$line: ${e.key}');
    }
    expect(f.note, note, reason: line);
  }

  void expectCustom(String line) {
    expect(single(line).isCustom, isTrue, reason: line);
  }

  group('the reading that explains more of the line wins', () {
    test('an amount the prefix match left in its note', () {
      expectReads('Larks allemande Left 1.5 (face P)', 'allemande', {
        'who': 'role1s',
        'travel': 1.5,
      }, note: 'face P');
      expectReads('Robins Do-si-do 1.5 (to new N)', 'do_si_do', {
        'travel': 1.5,
      }, note: 'to new N');
      expectReads('Circle Left 1/2 (with N2)', 'circle', {
        'places': 2,
      }, note: 'with N2');
      expectReads('Circle Left 3/4 (in cloverleaf)', 'circle', {
        'places': 3,
      }, note: 'in cloverleaf');
    });
  });

  group('an amount the readers cannot take stays custom', () {
    test('rather than the default amount', () {
      expectCustom('Circle Left 3/4, make short waves');
      expectCustom('Larks allemande Right 3/4 to P');
      expectCustom('Larks allemande Left 1.5, scoop N');
      expectCustom('Pass through 2 along the line');
    });

    test('a count with a unit is not an amount (#1863)', () {
      expectReads('neighbors swing 8 beats', 'swing', {
        'who': 'neighbors',
      }, note: '8 beats');
    });
  });

  group('decimal and hyphenated amounts', () {
    test('turns', () {
      expectReads('Robins allemande Right 0.5', 'allemande', {'travel': 0.5});
      expectReads('Shadow allemande Left 1.0', 'allemande', {
        'who': 'shadows',
        'travel': 1.0,
      });
      expectReads('Larks allemande Left 1-1/2', 'allemande', {'travel': 1.5});
      expectReads('Larks allemande Left 1-1/4', 'allemande', {'travel': 1.25});
      expectReads('Robins Do-si-do 1.0', 'do_si_do', {'travel': 1.0});
    });

    test('circle and star places', () {
      expectReads('Circle Left 1.0', 'circle', {'places': 4});
      expectReads('Circle Left 0.5', 'circle', {'places': 2});
      expectReads('Left-hand star 1.0', 'star', {'hand': 'left', 'places': 4});
      expectReads('Circle Left 5/4', 'circle', {'places': 5});
    });
  });

  group('a number after a dancer word is the dancer, not an amount', () {
    test('Neighbor 0-4 reads as the N-tag of that number', () {
      expectReads('Neighbor 2 Do-si-do', 'do_si_do', {'who': 'nextNeighbors'});
      expect(single('Neighbor 2 Do-si-do').params['travel'], isNull);
      expectReads('Neighbor 1 allemande Left 3/4', 'allemande', {
        'who': 'neighbors',
        'travel': 0.75,
      });
      expectReads('Neighbor 1 Right Shoulder Round 1/2', 'shoulder_round', {
        'who': 'neighbors',
        'travel': 0.5,
      });
      expectReads('Neighbor 3 swing', 'swing', {'who': 'thirdNeighbors'});
      expectReads('Neighbor 0 pull by Right', 'pull_by', {
        'who': 'prevNeighbors',
      });
    });

    test('any other number after a dancer word leaves the line custom', () {
      // Without the marking, "2" would be read as "twice".
      expectCustom('Partner 2 allemande Left');
      expectCustom('Neighbor 5 allemande Left');
    });
  });

  test('a dancer tag in brackets is kept as the note, not dropped', () {
    // Reading `1.0` lets this line structure; the tag must survive it.
    expectReads('(N2) Right-hand star 1.0', 'star', {
      'hand': 'right',
      'places': 4,
    }, note: 'N2');
  });

  test('a mixed number after a dancer word is the amount', () {
    // `_normalize` splits `1½` into `1 1/2`; the `1` must not fold into N1.
    expectReads('Allemande left neighbor 1½', 'allemande', {
      'who': 'neighbors',
      'travel': 1.5,
    });
    expectReads('Gypsy partner 1 1/2', 'shoulder_round', {
      'who': 'partners',
      'travel': 1.5,
    });
  });

  test('an amount spelled with a suffix or a full stop is still an amount', () {
    expectCustom('Circle Left 3/4. Make short waves');
    expectCustom('Circle left 3/4ths');
  });

  test('a single-file promenade clockwise is a single-file circle left', () {
    // With a note, so the ranking decides it: on `main` the promenade's own
    // reading won and noted the rest.
    expectReads('Single file promenade clockwise 3/4 (with N2)', 'circle', {
      'direction': 'left',
      'singleFile': true,
      'places': 3,
    }, note: '(with N2)');
    expectReads('Single file promenade clockwise 3/4', 'circle', {
      'direction': 'left',
      'singleFile': true,
      'places': 3,
    });
  });
}
