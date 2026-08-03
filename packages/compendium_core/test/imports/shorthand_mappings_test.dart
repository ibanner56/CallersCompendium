import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// A taxonomy-valid neighbor swing (16 beats).
Figure _swing({String who = 'neighbors', int beats = 16}) =>
    testFigure(move: 'swing', params: {'who': who, 'beats': beats});

/// A taxonomy-valid circle (used as a second figure in multi-figure mappings).
Figure _circle() => parseFreeTextFigureEntry('circle left 3/4').single;

void main() {
  group('normalizeShorthandToken', () {
    test('trims and lowercases', () {
      expect(normalizeShorthandToken('  BnS  '), 'bns');
      expect(normalizeShorthandToken('Nbr Bal & Swing'), 'nbr bal & swing');
    });
  });

  group('ShorthandMappings.resolve — matching', () {
    test('single-figure expansion returns the mapped figure', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      final result = mappings.resolve('bns');
      expect(result, hasLength(1));
      expect(result!.single.move, 'swing');
      expect(result.single.params['who'], 'neighbors');
    });

    test('multi-figure expansion preserves order (mini-macro)', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'combo', figures: [_swing(), _circle()]),
      ]);
      final result = mappings.resolve('combo');
      expect(result, hasLength(2));
      expect(result![0].move, 'swing');
      expect(result[1].move, 'circle');
    });

    test('match is case-insensitive and trim-insensitive', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'BnS', figures: [_swing()]),
      ]);
      expect(mappings.resolve('bns'), hasLength(1));
      expect(mappings.resolve('  BNS  '), hasLength(1));
      expect(mappings.resolve('Bns'), hasLength(1));
    });

    test('a miss returns null', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      expect(mappings.resolve('not a token'), isNull);
    });

    test('an empty/whitespace line returns null', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      expect(mappings.resolve(''), isNull);
      expect(mappings.resolve('   '), isNull);
    });

    test('resolve returns an independent, mutable copy', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      final a = mappings.resolve('bns')!;
      a.add(_circle());
      // A second resolve is unaffected by mutating the first result.
      expect(mappings.resolve('bns'), hasLength(1));
    });

    test('empty store resolves nothing', () {
      expect(ShorthandMappings.empty.resolve('bns'), isNull);
      expect(ShorthandMappings.empty.isEmpty, isTrue);
    });
  });

  group('parseFreeTextFigureEntry — shorthand precedence (#420)', () {
    test('shorthands are checked FIRST, before the parser', () {
      // "swing" is a perfectly parseable figure line, but a shorthand that
      // shadows it must win.
      final mappings = ShorthandMappings([
        ShorthandMapping(
          token: 'swing',
          figures: [_swing(who: 'partners', beats: 24)],
        ),
      ]);
      final result = parseFreeTextFigureEntry('swing', shorthands: mappings);
      expect(result, hasLength(1));
      expect(result.single.params['who'], 'partners');
      expect(result.single.params['beats'], 24);
    });

    test('a shorthand miss falls through to parseFigureLines', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      final result = parseFreeTextFigureEntry(
        'neighbor swing',
        shorthands: mappings,
      );
      expect(result, hasLength(1));
      expect(result.single.move, 'swing');
      expect(result.single.params['who'], 'neighbors');
    });

    test('matching is whole-line only — no mid-line substitution', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      // "bns" appears inside a longer line; it must NOT expand. The line falls
      // through to the parser and stays a custom (unrecognized) figure.
      final result = parseFreeTextFigureEntry(
        'bns then circle',
        shorthands: mappings,
      );
      expect(result, hasLength(1));
      expect(result.single.isCustom, isTrue);
    });

    test('case/trim-insensitive whole-line match still expands', () {
      final mappings = ShorthandMappings([
        ShorthandMapping(token: 'BnS', figures: [_swing(), _circle()]),
      ]);
      final result = parseFreeTextFigureEntry('  bns ', shorthands: mappings);
      expect(result, hasLength(2));
      expect(result[0].move, 'swing');
      expect(result[1].move, 'circle');
    });

    test('without a shorthand store the behavior is unchanged', () {
      final result = parseFreeTextFigureEntry('neighbor swing');
      expect(result.single.move, 'swing');
    });

    test('an empty store leaves parser behavior unchanged', () {
      final result = parseFreeTextFigureEntry(
        'neighbor swing',
        shorthands: ShorthandMappings.empty,
      );
      expect(result.single.move, 'swing');
    });
  });

  group('ShorthandMappings.decode — round-trip', () {
    test('encode → decode preserves tokens and ordered figures', () {
      final original = ShorthandMappings([
        ShorthandMapping(token: 'BnS', figures: [_swing()]),
        ShorthandMapping(token: 'combo', figures: [_swing(), _circle()]),
      ]);
      final decoded = ShorthandMappings.decode(
        original.encode(),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(2));
      expect(decoded.mappings[0].token, 'BnS'); // original casing preserved
      expect(decoded.mappings[0].figures.single.move, 'swing');
      expect(decoded.mappings[1].figures.map((f) => f.move), [
        'swing',
        'circle',
      ]);
    });

    test('accepts an already-decoded List as well as a JSON string', () {
      final original = ShorthandMappings([
        ShorthandMapping(token: 'bns', figures: [_swing()]),
      ]);
      final asList = original.toJson();
      final decoded = ShorthandMappings.decode(
        asList,
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(1));
      expect(decoded.mappings.single.token, 'bns');
    });
  });

  group('ShorthandMappings.decode — defensive guards (OWASP), never throws', () {
    test('null / non-List / wrong-typed input yields empty', () {
      expect(
        ShorthandMappings.decode(null, taxonomy: contraTaxonomy).isEmpty,
        isTrue,
      );
      expect(
        ShorthandMappings.decode(42, taxonomy: contraTaxonomy).isEmpty,
        isTrue,
      );
      expect(
        ShorthandMappings.decode({
          'not': 'a list',
        }, taxonomy: contraTaxonomy).isEmpty,
        isTrue,
      );
    });

    test('malformed JSON string yields empty', () {
      expect(
        ShorthandMappings.decode('{not json', taxonomy: contraTaxonomy).isEmpty,
        isTrue,
      );
      expect(
        ShorthandMappings.decode(
          '"a bare string"',
          taxonomy: contraTaxonomy,
        ).isEmpty,
        isTrue,
      );
    });

    test('entries that are not objects are skipped', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          'not an object',
          42,
          {
            'token': 'bns',
            'figures': [figureToJson(_swing())],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(1));
      expect(decoded.mappings.single.token, 'bns');
    });

    test('empty / whitespace / oversized / non-string tokens are dropped', () {
      final figs = [figureToJson(_swing())];
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {'token': '', 'figures': figs},
          {'token': '   ', 'figures': figs},
          {'token': 'x' * (maxShorthandTokenLength + 1), 'figures': figs},
          {'token': 123, 'figures': figs},
          {'token': 'ok', 'figures': figs},
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(1));
      expect(decoded.mappings.single.token, 'ok');
    });

    test('a token exactly at the length bound is kept', () {
      final token = 'x' * maxShorthandTokenLength;
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': token,
            'figures': [figureToJson(_swing())],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings.single.token, token);
    });

    test('empty, oversized, or non-list figure lists drop the mapping', () {
      final tooMany = [
        for (var i = 0; i < maxShorthandTargetFigures + 1; i++)
          figureToJson(_swing()),
      ];
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {'token': 'empty', 'figures': <Object?>[]},
          {'token': 'nolist', 'figures': 'nope'},
          {'token': 'toomany', 'figures': tooMany},
          {
            'token': 'ok',
            'figures': [figureToJson(_swing())],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(1));
      expect(decoded.mappings.single.token, 'ok');
    });

    test('a figure with an unknown move drops the whole mapping', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': 'bad',
            // invalid-fixture: move is deliberately outside the taxonomy — a figure with an unknown move drops the whole mapping
            'figures': [figureToJson(Figure(move: 'not_a_real_move'))],
          },
          {
            'token': 'ok',
            'figures': [figureToJson(_swing())],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(1));
      expect(decoded.mappings.single.token, 'ok');
    });

    test('an unknown param key drops the whole mapping', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': 'bad',
            'figures': [
              // invalid-fixture: param name is deliberately unknown — an unknown param key drops the whole mapping
              figureToJson(Figure(move: 'swing', params: {'bogus': 1})),
            ],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.isEmpty, isTrue);
    });

    test('an out-of-range param value drops the whole mapping', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': 'bad',
            'figures': [
              // beats domain is 0..64; 999 is non-conforming.
              // invalid-fixture: value is deliberately out of domain — an out-of-range param value drops the whole mapping
              figureToJson(Figure(move: 'swing', params: {'beats': 999})),
            ],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.isEmpty, isTrue);
    });

    test('a non-conforming enum/dancer value drops the whole mapping', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': 'bad',
            'figures': [
              // invalid-fixture: value is deliberately out of domain — a non-conforming enum/dancer value drops the whole mapping
              figureToJson(Figure(move: 'swing', params: {'who': 'aliens'})),
            ],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.isEmpty, isTrue);
    });

    test('all-or-nothing: one bad figure drops the whole (partial) mapping', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': 'partial',
            'figures': [
              figureToJson(_swing()), // good
              // invalid-fixture: move is deliberately outside the taxonomy — all-or-nothing: one bad figure drops the whole (partial) mapping
              figureToJson(Figure(move: 'not_a_real_move')), // bad
            ],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.isEmpty, isTrue);
    });

    test(
      'a structurally malformed figure (missing move) drops the mapping',
      () {
        final decoded = ShorthandMappings.decode(
          jsonEncode([
            {
              'token': 'bad',
              'figures': [
                <String, Object?>{'params': <String, Object?>{}}, // no "move"
              ],
            },
          ]),
          taxonomy: contraTaxonomy,
        );
        expect(decoded.isEmpty, isTrue);
      },
    );

    test('case-insensitive duplicate tokens keep the FIRST occurrence', () {
      final decoded = ShorthandMappings.decode(
        jsonEncode([
          {
            'token': 'BnS',
            'figures': [figureToJson(_swing(beats: 16))],
          },
          {
            'token': 'bns',
            'figures': [figureToJson(_swing(beats: 8))],
          },
        ]),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(1));
      expect(decoded.mappings.single.token, 'BnS');
      expect(decoded.mappings.single.figures.single.params['beats'], 16);
    });

    test('the mapping count is bounded to maxShorthandMappings', () {
      final entries = [
        for (var i = 0; i < maxShorthandMappings + 50; i++)
          {
            'token': 'tok$i',
            'figures': [figureToJson(_swing())],
          },
      ];
      final decoded = ShorthandMappings.decode(
        jsonEncode(entries),
        taxonomy: contraTaxonomy,
      );
      expect(decoded.mappings, hasLength(maxShorthandMappings));
    });

    test('never throws on assorted hostile payloads', () {
      final payloads = <Object?>[
        null,
        '',
        '[',
        '[{}]',
        jsonEncode([
          {'token': null, 'figures': null},
        ]),
        jsonEncode([
          {
            'token': 'x',
            'figures': [null, 1, 'str'],
          },
        ]),
        {'token': 'x'},
        [1, 2, 3],
      ];
      for (final p in payloads) {
        expect(
          () => ShorthandMappings.decode(p, taxonomy: contraTaxonomy),
          returnsNormally,
          reason: 'payload: $p',
        );
      }
    });
  });
}
