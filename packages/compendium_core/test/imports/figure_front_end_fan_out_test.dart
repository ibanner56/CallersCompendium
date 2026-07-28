import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A stub front-end whose pre-recognizer structures any scrubbed line that
/// satisfies [when] to a valid `swing`/neighbors figure carrying [note], so a
/// test can tell WHICH front-end produced a fan-out winner by its note. Because
/// it always carries a note it is a NOTE-BEARING (tier-2) attempt, which is
/// exactly what the precedence-within-a-tier tests below want (they compare
/// several note-bearing stubs, so the highest-precedence one wins). When [when]
/// is not satisfied the pre-recognizer returns null and the line falls to the
/// shared recognizers (which do not recognize the nonsense sentinels used here),
/// so the stub effectively "misses" and degrades to custom.
FigureFrontEnd _stub(String note, {required bool Function(String) when}) =>
    FigureFrontEnd(
      preRecognizers: [
        (scrubbed) => when(scrubbed.toLowerCase())
            ? FigureMatch('swing', params: {'who': 'neighbors'}, note: note)
            : null,
      ],
    );

/// A CLEAN (noteless) stub front-end that structures any line satisfying [when]
/// to a `swing` figure with the given [who], identifiable by that param rather
/// than a note. Used to test precedence WITHIN the clean (tier-1) band, where a
/// note would otherwise change the tier.
FigureFrontEnd _cleanStub(String who, {required bool Function(String) when}) =>
    FigureFrontEnd(
      preRecognizers: [
        (scrubbed) => when(scrubbed.toLowerCase())
            ? FigureMatch('swing', params: {'who': who})
            : null,
      ],
    );

bool _always(String _) => true;
bool _never(String _) => false;

void main() {
  // A nonsense sentinel the shared recognizers never structure, so ONLY a
  // stub's pre-recognizer can turn it non-custom.
  const sentinel = 'plover';

  group('figureFanOutFrontEnds (default precedence list)', () {
    test('is ordered ContraDB > CallersBox/TCB > CallersCompanion', () {
      expect(figureFanOutFrontEnds, hasLength(3));
      expect(
        identical(figureFanOutFrontEnds[0], contraDbHtmlFigureFrontEnd),
        isTrue,
      );
      expect(identical(figureFanOutFrontEnds[1], tcbFigureFrontEnd), isTrue);
      expect(
        identical(figureFanOutFrontEnds[2], callersCompanionFigureFrontEnd),
        isTrue,
      );
    });

    test('is unmodifiable', () {
      expect(
        () => figureFanOutFrontEnds.add(canonicalFigureFrontEnd),
        throwsUnsupportedError,
      );
    });
  });

  group('parseFigureLineFanOut — precedence ordering', () {
    test('highest-precedence non-custom result wins when >1 structures', () {
      final f = parseFigureLineFanOut(
        sentinel,
        frontEnds: [
          _stub('first', when: _always),
          _stub('second', when: _always),
          _stub('third', when: _always),
        ],
      );
      expect(f, isNotNull);
      expect(f!.isCustom, isFalse);
      expect(f.note, 'first');
    });

    test('a lower-precedence front-end is used only when higher ones miss', () {
      final f = parseFigureLineFanOut(
        sentinel,
        frontEnds: [
          _stub('first', when: _never), // misses -> custom
          _stub('second', when: _always), // wins
          _stub('third', when: _always),
        ],
      );
      expect(f!.isCustom, isFalse);
      expect(f.note, 'second');
    });

    test('the third front-end wins when the first two miss', () {
      final f = parseFigureLineFanOut(
        sentinel,
        frontEnds: [
          _stub('first', when: _never),
          _stub('second', when: _never),
          _stub('third', when: _always),
        ],
      );
      expect(f!.isCustom, isFalse);
      expect(f.note, 'third');
    });
  });

  group('parseFigureLineFanOut — custom fallback when all miss', () {
    test(
      'returns an import-gap custom preserving text, beats, progression',
      () {
        final f = parseFigureLineFanOut(
          'qwx zzz nonsense',
          beats: 8,
          progression: true,
          frontEnds: [
            _stub('a', when: _never),
            _stub('b', when: _never),
            _stub('c', when: _never),
          ],
        );
        expect(f, isNotNull);
        expect(f!.isCustom, isTrue);
        expect(f.customOrigin, CustomOrigin.importGap);
        expect(f.params['text'], 'qwx zzz nonsense');
        expect(f.params['beats'], 8);
        expect(f.progression, isTrue);
      },
    );

    test('returns null (nothing to store) when empty after scrubbing', () {
      expect(parseFigureLineFanOut('   '), isNull);
      expect(
        parseFigureLineFanOut('   ', frontEnds: [_stub('a', when: _always)]),
        isNull,
      );
    });

    test('an EMPTY frontEnds list is coalesced to the defaults (never drops '
        'a non-empty line)', () {
      // A structurable line still structures via the default precedence list.
      final structured = parseFigureLineFanOut('neighbor swing', frontEnds: []);
      expect(structured, isNotNull);
      expect(structured!.isCustom, isFalse);
      expect(structured.move, 'swing');
      // A nonsense line still becomes an import-gap custom, NOT dropped to null.
      final custom = parseFigureLineFanOut(
        'qwx zzz nonsense',
        beats: 4,
        frontEnds: [],
      );
      expect(custom, isNotNull);
      expect(custom!.isCustom, isTrue);
      expect(custom.customOrigin, CustomOrigin.importGap);
      expect(custom.params['beats'], 4);
    });
  });

  group(
    'parseFigureLineFanOut — structured result carries beats/progression',
    () {
      test(
        'a winning structured figure keeps the source beats and progression',
        () {
          final f = parseFigureLineFanOut(
            sentinel,
            beats: 12,
            progression: true,
            frontEnds: [_stub('win', when: _always)],
          );
          expect(f!.isCustom, isFalse);
          expect(f.move, 'swing');
          expect(f.params['beats'], 12);
          expect(f.progression, isTrue);
          expect(f.note, 'win');
        },
      );
    },
  );

  group('parseFigureLineFanOut — defaults reach the real front-ends', () {
    test('a plain line structures via the default precedence list', () {
      final f = parseFigureLineFanOut('neighbor swing');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
    });

    test('a TCB hey pass-list structures via the CallersBox attempt', () {
      // The parenthetical pass list is TCB-specific; the enriched ContraDB
      // front-end does not decode it, so the fan-out falls through to TCB.
      final f = parseFigureLineFanOut('hey 1/2 (ml;pr)');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'hey');
    });
  });

  group('parseFigureLineFanOut — ContraDB precedence (real enriched front-end)', () {
    // `slide left along set` renders ContraDB's slideAlongSetWords; only the
    // enriched contraDbHtmlFigureFrontEnd reverse-parses it. The shared/TCB
    // recognizers choke on the trailing "along set" and fall to custom, so this
    // line proves the fan-out actually consults ContraDB — and that ContraDB
    // sits at the FRONT of the precedence list.
    test('a ContraDB-only line structures via the ContraDB front-end', () {
      final f = parseFigureLineFanOut('slide left along set');
      expect(f, isNotNull);
      expect(f!.isCustom, isFalse);
      expect(f.move, 'slide_along_set');
      expect(f.params['slide'], 'left');
    });

    test(
      'the same line stays custom when ContraDB is removed from the fan-out',
      () {
        // With only TCB + CC, nothing reverse-parses "along set", so the win above
        // is attributable specifically to ContraDB's presence and precedence.
        final f = parseFigureLineFanOut(
          'slide left along set',
          frontEnds: [tcbFigureFrontEnd, callersCompanionFigureFrontEnd],
        );
        expect(f, isNotNull);
        expect(f!.isCustom, isTrue);
        expect(f.customOrigin, CustomOrigin.importGap);
      },
    );

    test('a ContraDB allemande carries its verbatim trailing note through the '
        'fan-out', () {
      // ContraDB appends a figure's free-text note with no separator; its
      // reverse-parser captures the tail as the figure note. TCB/CC would reject
      // the leftover prose and fall to custom, so a preserved note is a
      // ContraDB-front-end signature proving ContraDB produced the winner.
      final f = parseFigureLineFanOut(
        "role1s allemande left 1x - don't let go",
      );
      expect(f!.isCustom, isFalse);
      expect(f.move, 'allemande');
      expect(f.params['who'], 'role1s');
      expect(f.params['hand'], 'left');
      expect(f.note, "1x - don't let go");
    });

    test(
      'ContraDB wins over a lower-precedence front-end that also structures',
      () {
        // Place the REAL enriched ContraDB front-end ahead of a CLEAN stub that
        // would structure the same line to a DIFFERENT move: within the clean
        // tier, precedence decides, so the fan-out must take ContraDB's
        // slide_along_set, not the stub's swing.
        final f = parseFigureLineFanOut(
          'slide left along set',
          frontEnds: [
            contraDbHtmlFigureFrontEnd,
            _cleanStub('neighbors', when: _always),
          ],
        );
        expect(f!.isCustom, isFalse);
        expect(f.move, 'slide_along_set');
      },
    );

    test('a lower-precedence CLEAN front-end wins by position over another '
        'clean one ordered behind it', () {
      // Two clean stubs, distinguished by `who`: the FIRST (highest-precedence)
      // wins, confirming position governs within the clean tier.
      final f = parseFigureLineFanOut(
        'plover',
        frontEnds: [
          _cleanStub('partners', when: _always),
          _cleanStub('neighbors', when: _always),
        ],
      );
      expect(f!.isCustom, isFalse);
      expect(f.params['who'], 'partners');
    });

    test('a CLEAN lower-precedence parse beats a NOTE-BEARING higher one '
        '(balance & swing fidelity)', () {
      // The enriched ContraDB front-end reads "balance and swing" as a bare
      // `balance` and drops "and swing (NR)" into a note; TCB reads the whole
      // line cleanly as swing with a balance prefix. The clean TCB parse must
      // win over ContraDB's higher-precedence note-bearing one so the swing is
      // not silently lost.
      final f = parseFigureLineFanOut('neighbors balance and swing (NR)');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.params['prefix'], 'balance');
      expect(f.note, isNull);
    });

    test('a single line with a real fractional-places move prefers the clean '
        'TCB parse over ContraDBs note-bearing one', () {
      // "circle left 3/4": ContraDB captures "3/4" as a note (no fractional
      // places recognizer); TCB parses places:3. The clean TCB parse wins.
      final f = parseFigureLineFanOut('circle left 3/4');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'circle');
      expect(f.params['places'], 3);
      expect(f.note, isNull);
    });

    test('a note that swallowed a top-level `||` is rejected (stays custom)', () {
      // ContraDB would structure "circle left || swing" as circle with a
      // "|| swing" note; that note swallowed a simultaneity separator, so it is
      // rejected and the single-line path keeps the line custom.
      final f = parseFigureLineFanOut('circle left || swing');
      expect(f!.isCustom, isTrue);
      expect(f.customOrigin, CustomOrigin.importGap);
    });

    test('the plural entry point also structures a ContraDB-only line', () {
      final fs = parseFigureLinesFanOut('slide left along set');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.move, 'slide_along_set');
    });
  });

  group('parseFigureLinesFanOut — single line', () {
    test('a recognised single line yields one structured figure', () {
      final fs = parseFigureLinesFanOut('neighbor swing');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.move, 'swing');
    });

    test('empty after scrubbing yields no figures', () {
      expect(parseFigureLinesFanOut('   '), isEmpty);
    });

    test('an EMPTY frontEnds list is coalesced to the defaults (never drops '
        'a non-empty line)', () {
      final structured = parseFigureLinesFanOut(
        'neighbor swing',
        frontEnds: [],
      );
      expect(structured, hasLength(1));
      expect(structured.single.isCustom, isFalse);
      expect(structured.single.move, 'swing');

      final custom = parseFigureLinesFanOut('qwx zzz nonsense', frontEnds: []);
      expect(custom, hasLength(1));
      expect(custom.single.isCustom, isTrue);
      expect(custom.single.customOrigin, CustomOrigin.importGap);
    });
  });

  group('parseFigureLinesFanOut — segmentation (only TCB `;`-splits)', () {
    test(
      'a fully-structured `;`-compound splits via the CallersBox attempt',
      () {
        final fs = parseFigureLinesFanOut('Circle left 3/4; turn alone');
        expect(fs.map((f) => f.move), ['circle', 'turn_alone']);
        expect(fs.every((f) => !f.isCustom), isTrue);
      },
    );

    test(
      'all-or-nothing: an unstructurable clause keeps the whole line custom',
      () {
        final fs = parseFigureLinesFanOut('Circle left 3/4; yadda blorp');
        expect(fs, hasLength(1));
        expect(fs.single.isCustom, isTrue);
        expect(fs.single.customOrigin, CustomOrigin.importGap);
      },
    );

    test('a top-level `||` stays whole-custom (simultaneity not modelled)', () {
      final fs = parseFigureLinesFanOut('circle left || swing');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
    });

    test('front-ends other than TCB do NOT `;`-split the line', () {
      // With TCB excluded from the fan-out, the `;`-compound is never split:
      // each remaining front-end tries the whole line as one figure, which
      // cannot structure, so the line stays a single whole-line custom.
      final fs = parseFigureLinesFanOut(
        'Circle left 3/4; turn alone',
        frontEnds: [contraDbHtmlFigureFrontEnd, callersCompanionFigureFrontEnd],
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
    });
  });

  group('parseFigureLinesFanOut — precedence with injected front-ends', () {
    test('highest-precedence structured whole-line attempt wins', () {
      final fs = parseFigureLinesFanOut(
        'plover',
        frontEnds: [
          _stub('first', when: _always),
          _stub('second', when: _always),
        ],
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.note, 'first');
    });

    test('falls through to a lower front-end when the higher one misses', () {
      final fs = parseFigureLinesFanOut(
        'plover',
        frontEnds: [
          _stub('first', when: _never),
          _stub('second', when: _always),
        ],
      );
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.note, 'second');
    });

    test('all miss -> single import-gap custom carrying the line', () {
      final fs = parseFigureLinesFanOut(
        'qwx zzz nonsense',
        beats: 6,
        frontEnds: [
          _stub('a', when: _never),
          _stub('b', when: _never),
        ],
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.customOrigin, CustomOrigin.importGap);
      expect(fs.single.params['beats'], 6);
    });
  });
}
