import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'reference_jcs_encoder.dart';

void main() {
  group('canonicalJson', () {
    test('matches the independent wire corpus oracle', () {
      final corpus = jsonDecode(
        File('test/sync/fixtures/wire_corpus.json').readAsStringSync(),
      );

      expect(canonicalJson(corpus), referenceJcsEncode(corpus));
      expect(
        canonicalJson(corpus),
        '{"custom_field_values":{"value_num":4,'
        '"value_num_fractional":1.25},"optional":{"absent_is_not_serialized":null},'
        '"records":{"dance":{"shared-id":{"title":"Café"}},'
        '"program":{"shared-id":{"title":"Café"}}},'
        '"unicode":"line\\nquote\\"slash\\\\"}',
      );

      final roundTripped =
          jsonDecode(canonicalJson(corpus)) as Map<String, dynamic>;
      final records = roundTripped['records'] as Map<String, dynamic>;
      final dance = records['dance'] as Map<String, dynamic>;
      final program = records['program'] as Map<String, dynamic>;
      expect((dance['shared-id'] as Map<String, dynamic>)['title'], 'Café');
      expect((program['shared-id'] as Map<String, dynamic>)['title'], 'Café');
    });

    test('orders keys by UTF-16 code units and preserves nested values', () {
      expect(
        canonicalJson({
          '\u{10000}': 'astral',
          '\ue000': 'private',
          'a': [true, null, 2],
        }),
        '{"a":[true,null,2],"𐀀":"astral","":"private"}',
      );
    });

    test('uses RFC 8785 number spellings', () {
      const vectors = <String, String>{
        '0000000000000000': '0',
        '8000000000000000': '0',
        '0000000000000001': '5e-324',
        '8000000000000001': '-5e-324',
        '7fefffffffffffff': '1.7976931348623157e+308',
        'ffefffffffffffff': '-1.7976931348623157e+308',
        '4340000000000000': '9007199254740992',
        'c340000000000000': '-9007199254740992',
        '4430000000000000': '295147905179352830000',
        '44b52d02c7e14af5': '9.999999999999997e+22',
        '44b52d02c7e14af6': '1e+23',
        '44b52d02c7e14af7': '1.0000000000000001e+23',
        '444b1ae4d6e2ef4e': '999999999999999700000',
        '444b1ae4d6e2ef4f': '999999999999999900000',
        '444b1ae4d6e2ef50': '1e+21',
        '3eb0c6f7a0b5ed8c': '9.999999999999997e-7',
        '3eb0c6f7a0b5ed8d': '0.000001',
        '41b3de4355555553': '333333333.3333332',
        '41b3de4355555554': '333333333.33333325',
        '41b3de4355555555': '333333333.3333333',
        '41b3de4355555556': '333333333.3333334',
        '41b3de4355555557': '333333333.33333343',
        'becbf647612f3696': '-0.0000033333333333333333',
        '43143ff3c1cb0959': '1424953923781206.2',
      };

      for (final MapEntry(key: bits, value: expected) in vectors.entries) {
        expect(canonicalJson(_doubleFromBits(bits)), expected, reason: bits);
      }
    });

    test('hashes complete values and body values as lowercase SHA-256', () {
      expect(
        contentHash({'b': 1, 'a': 2}),
        'd3626ac30a87e6f7a6428233b3c68299976865fa5508e4267c5415c76af7a772',
      );
      expect(
        bodyHash({'a': 2}),
        '7e8059f495589fcd981232cc11d00b00da3802c01d688fa1cf1f6bed6e5bb33c',
      );
    });

    test('rejects non-finite numbers', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => canonicalJson(value), throwsFormatException);
      }
    });

    test('rejects unpaired UTF-16 surrogates in keys and values', () {
      for (final value in [
        '\ud800',
        '\udfff',
        {'\ud800': 'ok'},
        {'ok': '\udfff'},
      ]) {
        expect(() => canonicalJson(value), throwsFormatException);
      }
    });

    test('preserves valid surrogate pairs', () {
      expect(canonicalJson('𐀀'), '"𐀀"');
    });

    test('emits stored strings without outbound normalization', () {
      final decomposed = 'Cafe\u0301';
      final composed = 'Café';
      expect(normalizeShareableText(decomposed), composed);
      expect(canonicalJson(decomposed), isNot(canonicalJson(composed)));
    });

    test('rejects non-string map keys recursively', () {
      expect(
        () => canonicalJson({
          'nested': {1: 'bad'},
        }),
        throwsFormatException,
      );
    });

    test('rejects cyclic lists and maps', () {
      final list = <Object?>[];
      list.add(list);
      final map = <String, Object?>{};
      map['self'] = map;

      expect(() => canonicalJson(list), throwsFormatException);
      expect(() => canonicalJson(map), throwsFormatException);
    });

    test('rejects integers that cannot be represented exactly as doubles', () {
      expect(() => canonicalJson(9007199254740993), throwsFormatException);
    });

    test('keeps same-id records nested by kind', () {
      final records = {
        'records': {
          'dance': {
            'same-id': {'title': 'Dance'},
          },
          'program': {
            'same-id': {'title': 'Program'},
          },
        },
      };
      final encoded = canonicalJson(records);
      expect(encoded, contains('"dance":{"same-id"'));
      expect(encoded, contains('"program":{"same-id"'));
    });
  });
}

double _doubleFromBits(String hex) {
  final bytes = ByteData(8)
    ..setUint32(0, int.parse(hex.substring(0, 8), radix: 16))
    ..setUint32(4, int.parse(hex.substring(8), radix: 16));
  return bytes.getFloat64(0);
}
