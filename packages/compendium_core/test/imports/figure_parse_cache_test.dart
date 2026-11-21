import 'dart:convert';
import 'dart:isolate';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// The figure parser keeps a few small caches — the last line's tokenization,
/// the last scrub, the canonical-dialect substitutors, and (per `.USR` adapter)
/// the figures a body line parsed to. Each is meant to change what parsing
/// COSTS and nothing it returns. These tests hunt for the ways a cache can lie:
/// a result that leaks from one line to the next, and a cache applied to a
/// dialect, synonym set or line it was not built for.

/// Stock calls plus the wordings that stress the parser: notes, `;` compounds,
/// `||` and `while` containers, fractions, casing, punctuation and gendered
/// terms. Variants of each are added by [_corpus].
const List<String> _stock = [
  '(8) Partner swing',
  '(16) Neighbor balance and swing',
  '(8) Ladies chain to partner',
  '(8) Right and left through',
  '(8) In long lines, go forward and back',
  '(8) Circle left 3 places',
  '(8) Hey for four',
  '(8) Gents allemande left 1 1/2',
  '(8) Star right 3/4 [with N2]',
  '(8) Petronella spin',
  '(8) Ladies allemande right 1 1/2 with neighbor',
  '(8) Men do si do 1 1/2',
  '(8) Gypsy partner 1 1/2, see-saw neighbor',
  '(8) Mad robin, ladies in front',
  '(8) Balance the ring, petronella',
  '(8) Slice left, forward and back',
  '(8) Women walk forward; form long wave in center; men turn around',
  '(4) Circle left; face up',
  '(8) Balance the ring || California twirl',
  '(8) Partners swap while neighbors circle',
  '(8) Swing your partner, robins chain',
  '(8) A thing nobody has ever written down before',
  '(8) Larks allemande left, robins allemande right',
  '',
];

List<String> _corpus() {
  final lines = <String>[];
  for (var i = 0; i < _stock.length; i++) {
    final t = _stock[i];
    lines.addAll([
      t,
      t.toUpperCase(),
      '$t (NR)',
      '$t!',
      t.replaceAll(' ', ', '),
      t.replaceAll('(', '[').replaceAll(')', ']'),
      '  ${t.replaceAll(' ', '  ')}  ',
      '$t; ${_stock[(i * 7 + 3) % _stock.length]}',
      '$t while ${_stock[(i * 5 + 1) % _stock.length]}',
    ]);
  }
  return lines;
}

/// Parses [line] the way the `.USR` importer does: the beats prefix is split
/// off first, so the front-ends see only the wording.
List<Figure> _parse(String line) {
  final prefix = splitCcBeatPrefix(line.trim());
  return parseFigureLinesFanOut(prefix.text, beats: prefix.beats);
}

/// The ContraDB front-end alone. The fan-out falls back to the other
/// front-ends when it declines a line, and for the stock calls they structure
/// the same figures — so a corrupted ContraDB scan can hide behind the fan-out's
/// final answer. Checked directly, it cannot.
Figure? _contraDb(String line) {
  final prefix = splitCcBeatPrefix(line.trim());
  return parseContraDbFigureLine(prefix.text, beats: prefix.beats);
}

/// What a line parses to, from an isolate that has parsed nothing else.
///
/// The caches are statics, so each isolate has its own and a fresh one starts
/// empty: this is the oracle a cache cannot influence. Comparing a function
/// only with itself (cold vs warm) cannot catch a cache that ignores its key —
/// every call would return the same wrong answer.
Future<({List<Figure> fanOut, Figure? contraDb})> _fromFreshIsolate(
  String line,
) => Isolate.run(() => (fanOut: _parse(line), contraDb: _contraDb(line)));

void main() {
  final corpus = _corpus();

  group('line-keyed caches never leak between lines', () {
    test(
      'every line parses as it does in an isolate that saw only that line',
      () async {
        // In-process the caches hold whatever ran before; the oracle holds only
        // the line itself. Each line is checked cold (after an unrelated one),
        // warm (straight after itself) and interleaved (after its neighbour).
        for (var i = 0; i < corpus.length; i++) {
          final line = corpus[i];
          final expected = await _fromFreshIsolate(line);
          void check(String when) {
            expect(
              _parse(line),
              equals(expected.fanOut),
              reason: '$when: <$line>',
            );
            expect(
              _contraDb(line),
              equals(expected.contraDb),
              reason: 'ContraDB, $when: <$line>',
            );
          }

          _parse('(8) Something $i that no cache holds yet, honest');
          check('cold');
          check('warm');
          _parse(corpus[(i + 1) % corpus.length]);
          check('after another line');
        }
      },
    );

    test('distinct lines in a row give their own answers', () {
      // A cache that ignored its key would hand the first line's figures to the
      // rest; these are semantically unmistakable.
      String move(String line) => _parse(line).single.move;
      final swing = move('(8) Partners swing');
      final chain = move('(8) Ladies chain to partner');
      final circle = move('(8) Circle left 3 places');
      expect({swing, chain, circle}, hasLength(3));
      expect(move('(8) Partners swing'), swing);
      expect(move('(8) Ladies chain to partner'), chain);
      expect(_contraDb('(8) Partners swing')?.move, swing);
      expect(_contraDb('(8) Circle left 3 places')?.move, circle);
    });

    test('an equal but distinct string hits the same result', () async {
      for (final line in _stock.where((l) => l.isNotEmpty)) {
        final copy = String.fromCharCodes(line.codeUnits);
        expect(identical(copy, line), isFalse);
        _parse('(8) An unrelated line');
        final expected = await _fromFreshIsolate(line);
        expect(_parse(copy), equals(expected.fanOut), reason: '<$line>');
        expect(_contraDb(copy), equals(expected.contraDb), reason: '<$line>');
      }
    });

    test(
      'scrubFigureText matches an isolate that scrubbed only that line',
      () async {
        for (var i = 0; i < corpus.length; i++) {
          final line = corpus[i];
          final expected = await Isolate.run(() => scrubFigureText(line));
          scrubFigureText('an unrelated line $i');
          expect(scrubFigureText(line), expected, reason: 'cold: <$line>');
          expect(scrubFigureText(line), expected, reason: 'warm: <$line>');
          scrubFigureText(corpus[(i + 3) % corpus.length]);
          expect(scrubFigureText(line), expected, reason: 'after: <$line>');
        }
      },
    );

    test('scrubFigureText gives distinct lines their own answers', () {
      expect(scrubFigureText('gents swing'), 'role1s swing');
      expect(scrubFigureText('ladies swing'), 'role2s swing');
      expect(scrubFigureText('gents swing'), 'role1s swing');
    });
  });

  group('the canonical-dialect substitutors', () {
    const texts = [
      'gents allemande left, ladies chain',
      'Larks and Robins swing',
      'MEN do si do, WOMEN gypsy',
      'the gentlespoon and the ladle',
      'mad robin, robins in front',
      'nothing to rewrite here',
      '',
    ];

    test('the cached path equals a freshly built one', () {
      // `copyWith()` is equal to `Dialect.canonical` but not identical to it,
      // so it is always built per call — the reference the cached path must
      // match.
      final reference = Dialect.canonical.copyWith();
      expect(identical(reference, Dialect.canonical), isFalse);
      for (final text in [...texts, ...corpus]) {
        // Run it twice so the second is served from whatever the first cached.
        for (var pass = 0; pass < 2; pass++) {
          final cached = canonicalize(text, Dialect.canonical);
          final built = canonicalize(text, reference);
          expect(cached.text, built.text, reason: '<$text> pass $pass');
          expect(
            cached.discouraged,
            equals(built.discouraged),
            reason: '<$text> pass $pass',
          );
          expect(
            canonicalizeText(text, Dialect.canonical),
            built.text,
            reason: '<$text> pass $pass',
          );
        }
      }
    });

    test('a cache built for the canonical dialect is not used for another', () {
      canonicalizeText('warm the canonical cache', Dialect.canonical);
      // The canonical dialect leaves `lead`/`follow` alone; Leads/Follows maps
      // them to the role tokens.
      expect(
        canonicalizeText('lead swings follow', Dialect.canonical),
        'lead swings follow',
      );
      expect(
        canonicalizeText('lead swings follow', Dialect.leadsFollows),
        'role1 swings role2',
      );
      expect(
        canonicalize('lead swings follow', Dialect.leadsFollows).text,
        'role1 swings role2',
      );
    });

    test('extra role synonyms bypass the cache and never stick to it', () {
      canonicalizeText('warm the canonical cache', Dialect.canonical);
      const extra = {'zog': 'role1'};
      expect(
        canonicalizeText(
          'zog dances',
          Dialect.canonical,
          extraRoleSynonyms: extra,
        ),
        'role1 dances',
      );
      expect(
        canonicalize(
          'zog dances',
          Dialect.canonical,
          extraRoleSynonyms: extra,
        ).text,
        'role1 dances',
      );
      // ...and did not leak into the plain canonical path afterwards.
      expect(canonicalizeText('zog dances', Dialect.canonical), 'zog dances');
    });
  });

  group('CcFigureLineCache', () {
    CcDanceRecord record(List<String> lines, {String name = 'Dance'}) =>
        CcDanceRecord(
          name: name,
          body: [CcBodySection(label: 'A1', lines: lines)],
        );

    test('mapping with a cache equals mapping without one', () {
      final cache = CcFigureLineCache();
      for (var i = 0; i < corpus.length; i += 3) {
        final rec = record([
          corpus[i],
          corpus[(i + 1) % corpus.length],
          corpus[i], // a repeat within the dance
        ]);
        final plain = mapCallersCompanionDance(rec);
        // Twice: the second is served from the cache the first filled.
        for (var pass = 0; pass < 2; pass++) {
          final cached = mapCallersCompanionDance(rec, lineCache: cache);
          expect(figuresOf(cached.dance), equals(figuresOf(plain.dance)));
          expect([
            for (final x in cached.issues) '${x.code}:${x.message}',
          ], equals([for (final x in plain.issues) '${x.code}:${x.message}']));
        }
      }
      expect(cache.length, greaterThan(0));
    });

    test('dances share the cached figures, which cannot be modified', () {
      final cache = CcFigureLineCache();
      final a = figuresOf(
        mapCallersCompanionDance(
          record(['(8) Partner swing']),
          lineCache: cache,
        ).dance,
      );
      final b = figuresOf(
        mapCallersCompanionDance(
          record(['(8) Partner swing'], name: 'Other'),
          lineCache: cache,
        ).dance,
      );
      expect(b, equals(a));
      expect(identical(a.single, b.single), isTrue);
      expect(
        () => cache['(8) Partner swing']!.add(a.single),
        throwsUnsupportedError,
      );
    });

    test('is keyed on the trimmed line, beats prefix included', () {
      final cache = CcFigureLineCache();
      mapCallersCompanionDance(record(['(8) Partner swing']), lineCache: cache);
      mapCallersCompanionDance(
        record(['   (8) Partner swing   ']),
        lineCache: cache,
      );
      expect(cache.length, 1);
      // A different beat count is a different line with different figures.
      final sixteen = figuresOf(
        mapCallersCompanionDance(
          record(['(16) Partner swing']),
          lineCache: cache,
        ).dance,
      );
      expect(cache.length, 2);
      expect(sixteen.single.beats, 16);
    });

    test('is bounded: past its cap lines still parse, none is evicted', () {
      final cache = CcFigureLineCache(maxEntries: 2);
      final lines = [
        '(8) Partner swing',
        '(8) Hey for four',
        '(8) Circle left',
      ];
      for (var round = 0; round < 3; round++) {
        for (final line in lines) {
          final cached = figuresOf(
            mapCallersCompanionDance(record([line]), lineCache: cache).dance,
          );
          expect(
            cached,
            equals(figuresOf(mapCallersCompanionDance(record([line])).dance)),
            reason: 'round $round: <$line>',
          );
        }
      }
      expect(cache.length, 2);
      expect(cache['(8) Partner swing'], isNotNull);
      expect(cache['(8) Hey for four'], isNotNull);
      expect(cache['(8) Circle left'], isNull);
    });

    test('an adapter parses each dance as a fresh one would', () {
      RawRecord raw(int i, String lines) => RawRecord(
        source: ProvenanceSource.callersCompanion,
        externalId: '$i',
        payload: jsonEncode({
          'rowId': '$i',
          'columns': {'Name': 'Dance $i', 'A1': lines},
        }),
        contentType: 'application/json',
      );

      final shared = CallersCompanionUsrAdapter();
      for (var i = 0; i < corpus.length; i += 4) {
        final lines = [
          corpus[i],
          corpus[(i + 5) % corpus.length],
          corpus[i],
        ].join('\n');
        final viaShared = shared.parse(raw(i, lines));
        final viaFresh = CallersCompanionUsrAdapter().parse(raw(i, lines));
        expect(
          figuresOf(viaShared.dance),
          equals(figuresOf(viaFresh.dance)),
          reason: 'dance $i',
        );
        expect([
          for (final x in viaShared.issues) '${x.code}:${x.message}',
        ], equals([for (final x in viaFresh.issues) '${x.code}:${x.message}']));
      }
    });
  });
}
