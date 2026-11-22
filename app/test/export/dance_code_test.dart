import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_app/src/export/dance_code.dart';
import 'package:compendium_app/src/export/dance_share_bundle.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 22);

/// The six-figure seed dance, through the real share-bundle builder.
String _bundle({String? title, String? walkthrough}) {
  final read = decodeArchive(
    File('assets/seed/baby_rose.json').readAsStringSync(),
  );
  if (read.errors.isNotEmpty) throw StateError('seed: ${read.errors}');
  var dance = read.archive.dances.single;
  dance = dance.copyWith(
    title: title ?? dance.title,
    walkthrough: walkthrough ?? dance.walkthrough,
  );
  final people = {for (final c in read.archive.choreographers) c.id: c};
  return buildDanceShareBundle(
    dance,
    choreographerFor: (id) => people[id],
    tagFor: (_) => null,
    publishedSourceFor: (_) => null,
    customFieldFor: (_) => null,
    now: _now,
  );
}

/// Deterministic prose-like text that compresses about as English does.
String _prose(int length) {
  const words = [
    'balance',
    'circle',
    'left',
    'swing',
    'allemande',
    'partner',
    'neighbor',
    'gents',
    'ladies',
    'robins',
    'larks',
    'promenade',
    'star',
    'right',
    'forward',
    'back',
    'petronella',
    'hey',
    'chain',
    'down',
    'the',
    'hall',
    'ones',
    'twos',
    'across',
    'set',
    'slide',
    'pass',
    'through',
    'on',
    'to',
  ];
  final out = StringBuffer();
  var state = 12345;
  while (out.length < length) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    out
      ..write(words[(state >> 8) % words.length])
      ..write(' ');
  }
  return out.toString().substring(0, length);
}

/// A link whose payload is [length] bytes long overall. Not decodable; the
/// planner only measures it.
String _linkOfLength(int length) =>
    danceLinkPrefix + 'A' * (length - danceLinkPrefix.length);

Uint8List _deflate(List<int> bytes) =>
    Uint8List.fromList(ZLibCodec(raw: true, level: 9).encode(bytes));

String _linkFor(List<int> deflated) =>
    '$danceLinkPrefix${base64Url.encode(deflated).replaceAll('=', '')}';

DanceLinkFailure _failureOf(String link, {int? cap}) {
  try {
    decodeDanceLink(link, maxInflatedBytes: cap ?? kMaxDanceInflatedBytes);
  } on DanceLinkException catch (e) {
    return e.failure;
  }
  fail('expected $link to be refused');
}

void main() {
  group('encode and decode', () {
    test('a dance link decodes to exactly the bundle JSON', () {
      final json = _bundle();
      final link = encodeDanceLink(json);
      expect(decodeDanceLink(link), json);
      // No state is kept between calls.
      expect(decodeDanceLink(encodeDanceLink(json)), json);
    });

    test('keeps characters outside Latin-1 byte for byte', () {
      final json = _bundle(title: 'Æblegrød 薔薇の舞 🌹 café');
      expect(json, contains('薔薇の舞'));
      expect(decodeDanceLink(encodeDanceLink(json)), json);
    });

    test('is the versioned prefix and unpadded Base64url, nothing else', () {
      expect(encodeDanceLink(_bundle()), startsWith('ccdance://1/'));
      // Padding only appears when the compressed length is not a multiple of
      // three, so sweep inputs until every remainder has been seen; a
      // single input can pass for a padded encoder by luck.
      final remainders = <int>{};
      for (var extra = 0; extra < 12; extra++) {
        final json = '{"a":"${'x' * extra}${_prose(extra * 7)}"}';
        final link = encodeDanceLink(json);
        final payload = link.substring(danceLinkPrefix.length);
        remainders.add(_deflate(utf8.encode(json)).length % 3);
        expect(payload, matches(r'^[A-Za-z0-9_-]+$'), reason: json);
        expect(decodeDanceLink(link), json);
      }
      expect(remainders, {0, 1, 2}, reason: 'the sweep must reach each case');
    });
  });

  group('planDanceCode tiers', () {
    test('the seed dance shows at level H with the mark', () {
      final plan = planDanceCode(_bundle());
      expect(plan, isA<DanceCodeShown>());
      plan as DanceCodeShown;
      expect(plan.level, DanceCodeLevel.high);
      expect(plan.withMark, isTrue);
      expect(plan.moduleCount, plan.version * 4 + 17);
      expect(plan.link, encodeDanceLink(_bundle()));
    });

    test(
      'a dance over the H limit drops to a lower level, without the mark',
      () {
        final json = _bundle(walkthrough: _prose(1300));
        final bytes = encodeDanceLink(json).length;
        // The fixture must really sit between the H and Q limits.
        expect(bytes, inInclusiveRange(1274, 1663));
        final plan = planDanceCode(json);
        expect(plan, isA<DanceCodeShown>());
        plan as DanceCodeShown;
        expect(plan.level, DanceCodeLevel.quartile);
        expect(plan.withMark, isFalse);
      },
    );

    test('a dance over every limit is too long', () {
      final json = _bundle(walkthrough: _prose(20000));
      final plan = planDanceCode(json);
      expect(plan, isA<DanceCodeTooLong>());
      expect(
        (plan as DanceCodeTooLong).linkBytes,
        greaterThan(DanceCodeLevel.low.byteCapacity),
      );
    });
  });

  group('capacity', () {
    test('each level takes a link of exactly its capacity and no more', () {
      // ISO/IEC 18004, version 40, byte mode. Literals, not the enum's own
      // numbers, so a wrong constant cannot agree with itself.
      const capacity = {
        DanceCodeLevel.high: 1273,
        DanceCodeLevel.quartile: 1663,
        DanceCodeLevel.medium: 2331,
        DanceCodeLevel.low: 2953,
      };
      for (final level in DanceCodeLevel.values) {
        expect(level.byteCapacity, capacity[level], reason: '$level');
        final atCap = planDanceLink(_linkOfLength(capacity[level]!));
        expect(atCap, isA<DanceCodeShown>(), reason: '$level at capacity');
        // The strongest level that fits is used, so a link of exactly this
        // level's capacity is at this level.
        expect((atCap as DanceCodeShown).level, level);
        expect(atCap.version, 40);
        final over = planDanceLink(_linkOfLength(capacity[level]! + 1));
        if (level == DanceCodeLevel.low) {
          expect(over, isA<DanceCodeTooLong>());
        } else {
          expect(
            (over as DanceCodeShown).level.index,
            greaterThan(level.index),
            reason: 'one byte over $level moves to a weaker level',
          );
        }
      }
    });

    test('a version cap moves a code to a lower level, never over the cap', () {
      final json = _bundle();
      final unlimited = planDanceCode(json) as DanceCodeShown;
      // The seed needs version 31 at H.
      expect(unlimited.version, greaterThan(1));
      final capped = planDanceCode(json, maxVersion: unlimited.version);
      expect((capped as DanceCodeShown).level, DanceCodeLevel.high);
      final tighter =
          planDanceCode(json, maxVersion: unlimited.version - 1)
              as DanceCodeShown;
      expect(tighter.level, isNot(DanceCodeLevel.high));
      expect(tighter.withMark, isFalse);
      expect(tighter.version, lessThan(unlimited.version));
      expect(planDanceCode(json, maxVersion: 1), isA<DanceCodeTooLong>());
      expect(() => planDanceCode(json, maxVersion: 41), throwsRangeError);
    });

    test('the module grid has the finder and timing patterns of a QR code', () {
      for (final length in [100, 778, 1201, 1273, 1663, 2331, 2953]) {
        final plan = planDanceLink(_linkOfLength(length)) as DanceCodeShown;
        final n = plan.moduleCount;
        // Timing patterns alternate along row 6 and column 6, dark first,
        // between the finder patterns. A grid rebuilt with the wrong module
        // size or offset would not alternate.
        for (var i = 8; i < n - 8; i++) {
          expect(plan.isDark(6, i), i.isEven, reason: 'row 6, col $i, n=$n');
          expect(plan.isDark(i, 6), i.isEven, reason: 'col 6, row $i, n=$n');
        }
        // The 7x7 finder pattern: dark ring, light ring, dark 3x3 core.
        for (final (r0, c0) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
          for (var r = 0; r < 7; r++) {
            for (var c = 0; c < 7; c++) {
              final ring = [r, c].any((v) => v == 0 || v == 6);
              final core = r >= 2 && r <= 4 && c >= 2 && c <= 4;
              expect(plan.isDark(r0 + r, c0 + c), ring || core);
            }
          }
        }
      }
    });
  });

  group('decodeDanceLink refuses', () {
    final good = encodeDanceLink(_bundle());

    test('anything that is not a dance link', () {
      for (final link in [
        '',
        'https://example.com/1/abc',
        'ccdance:1/abc',
        'ccdance://',
        'ccdance://1',
        'ccdance:///abc',
        'callerscompendium://1/abc',
      ]) {
        expect(_failureOf(link), DanceLinkFailure.notADanceLink, reason: link);
      }
    });

    test('a version this build does not read', () {
      final payload = good.substring(danceLinkPrefix.length);
      for (final version in ['0', '2', '10', 'v1', '01']) {
        expect(
          _failureOf('ccdance://$version/$payload'),
          DanceLinkFailure.unknownVersion,
          reason: version,
        );
      }
    });

    test('a payload that is not unpadded Base64url', () {
      final payload = good.substring(danceLinkPrefix.length);
      expect(
        _failureOf('$danceLinkPrefix$payload='),
        DanceLinkFailure.malformedBase64,
      );
      expect(
        _failureOf('${danceLinkPrefix}ab+/'),
        DanceLinkFailure.malformedBase64,
      );
      expect(
        _failureOf('${danceLinkPrefix}ab cd'),
        DanceLinkFailure.malformedBase64,
      );
      // Five characters is not a whole number of bytes in any padding.
      expect(
        _failureOf('${danceLinkPrefix}abcde'),
        DanceLinkFailure.malformedBase64,
      );
      expect(_failureOf(danceLinkPrefix), DanceLinkFailure.empty);
    });

    test('bytes that are not a DEFLATE stream', () {
      expect(
        _failureOf(_linkFor(Uint8List.fromList(List.filled(40, 0xFF)))),
        DanceLinkFailure.inflateFailed,
      );
    });

    test('a stream that inflates to nothing, bytes that are not UTF-8, and '
        'text that is not a JSON object', () {
      expect(_failureOf(_linkFor(_deflate(const []))), DanceLinkFailure.empty);
      expect(
        _failureOf(_linkFor(_deflate(const [0xC3, 0x28]))),
        DanceLinkFailure.notUtf8,
      );
      expect(
        _failureOf(_linkFor(_deflate(utf8.encode('[1,2]')))),
        DanceLinkFailure.notAJsonObject,
      );
      expect(
        _failureOf(_linkFor(_deflate(utf8.encode('{"a":')))),
        DanceLinkFailure.notAJsonObject,
      );
    });

    test('a truncated link is never returned as a shorter dance', () {
      // `dart:io` does not report a cut-short DEFLATE stream: it returns what
      // it has. At every cut point the link must be refused, or give back the
      // whole bundle; never a prefix.
      final json = _bundle(walkthrough: _prose(3000));
      final deflated = _deflate(utf8.encode(json));
      var partial = 0;
      for (var cut = 0; cut < deflated.length; cut++) {
        final slice = deflated.sublist(0, cut);
        final raw = ZLibDecoder(raw: true).convert(slice);
        if (raw.isNotEmpty && raw.length < utf8.encode(json).length) partial++;
        try {
          expect(decodeDanceLink(_linkFor(slice)), json, reason: 'cut $cut');
        } on DanceLinkException {
          // Refused, as it should be.
        }
      }
      // The sweep is only meaningful if the raw decoder really does hand back
      // partial text for some cuts; if it ever stops, this says so.
      expect(partial, greaterThan(0), reason: 'no cut yielded partial text');
    });
  });

  group('inflate cap', () {
    test('a 50 MiB bomb is refused without being inflated', () {
      const cap = 1024 * 1024;
      final bomb = _deflate(Uint8List(50 * 1024 * 1024));
      expect(bomb.length, lessThan(100 * 1024));
      var inflated = 0;
      Object? thrown;
      try {
        decodeDanceLink(
          _linkFor(bomb),
          maxInflatedBytes: cap,
          onInflated: (total) => inflated = total,
        );
      } on DanceLinkException catch (e) {
        thrown = e.failure;
      }
      expect(thrown, DanceLinkFailure.tooLarge);
      // The stream is abandoned at the cap, not read to the end.
      expect(inflated, greaterThan(cap));
      expect(inflated, lessThan(4 * cap));
    });

    test('output exactly at the cap is accepted, one byte over is not', () {
      // {"a":"xxxx"} padded to the length wanted.
      String objectOf(int length) {
        const frame = '{"a":""}';
        return '{"a":"${'x' * (length - frame.length)}"}';
      }

      final link = _linkFor(_deflate(utf8.encode(objectOf(2000))));
      expect(decodeDanceLink(link, maxInflatedBytes: 2000), objectOf(2000));
      expect(_failureOf(link, cap: 1999), DanceLinkFailure.tooLarge);
    });
  });
}
