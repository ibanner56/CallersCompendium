import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the ARB conventions in `docs/dev/localization.md` ("Key-naming
/// convention"): keys are lowerCamelCase, every key has an `@key` block with a
/// non-empty `description`, and placeholders are named and typed in the
/// metadata. Coverage, parity and quote style are gated elsewhere
/// (`tools/ci/check_arb_*.py`); these were conventions only.
///
/// Reads `app_en.arb`, the template every other locale follows. Each rule is a
/// function over the parsed map, so the same code runs on the real file (which
/// must be clean) and on small synthetic ARBs that must trip it, naming the key.
///
/// **Not asserted, on purpose:** an area prefix on every key. The ~50 leading
/// segments in use are an observation, not a registry: an allowlist of them would
/// turn each new feature area into a failing build plus a doc edit.
///
/// `app/l10n.yaml` sets no `use-escaping`, so gen-l10n reads `'` as an ordinary
/// character and `{`/`}` as the only structure; [icuArguments] relies on that.
Map<String, dynamic> _enArb() =>
    jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Message keys: everything that is not `@key` metadata or an `@@global`.
Iterable<String> messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

final _keyShape = RegExp(r'^[a-z][a-zA-Z0-9]*$');

/// Keys that are not lowerCamelCase: no underscores, dots, spaces or leading
/// capital.
List<String> badKeyNames(Map<String, dynamic> arb) => [
  for (final key in messageKeys(arb))
    if (!_keyShape.hasMatch(key)) '$key: not lowerCamelCase ($_keyShape)',
];

/// Message keys with no `@key` object, or whose `description` is missing, not a
/// string, or blank.
List<String> missingDescriptions(Map<String, dynamic> arb) {
  final problems = <String>[];
  for (final key in messageKeys(arb)) {
    final meta = arb['@$key'];
    if (meta is! Map) {
      problems.add('$key: no @$key metadata block');
      continue;
    }
    final description = meta['description'];
    if (description is! String || description.trim().isEmpty) {
      problems.add('$key: @$key has no non-empty description');
    }
  }
  return problems;
}

/// `@key` metadata for a key that does not exist.
List<String> orphanMetadata(Map<String, dynamic> arb) => [
  for (final key in arb.keys)
    if (key.startsWith('@') &&
        !key.startsWith('@@') &&
        !arb.containsKey(key.substring(1)))
      '$key: metadata for a message key that does not exist',
];

/// The argument names a message uses: `{name}`, and the selector argument of
/// `{n, plural, ...}` / `{g, select, ...}` / `{n, selectordinal, ...}` together
/// with every argument inside their sub-messages. Formatted arguments
/// (`{d, date, yMd}`) count by name. Throws [FormatException] on an unmatched
/// `{` or an argument with no name. A stray `}` is not checked: whether
/// gen-l10n rejects one is unconfirmed, and this test must not be stricter
/// than the generator.
Set<String> icuArguments(String message) {
  final names = <String>{};
  _collectArguments(message, names);
  return names;
}

int _closingBrace(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}' && --depth == 0) return i;
  }
  throw FormatException('unbalanced "{" in message', text, open);
}

void _collectArguments(String text, Set<String> names) {
  var i = 0;
  while (i < text.length) {
    if (text[i] != '{') {
      i++;
      continue;
    }
    final close = _closingBrace(text, i);
    final parts = text.substring(i + 1, close).split(',');
    final name = parts.first.trim();
    if (name.isEmpty) {
      throw FormatException('empty argument name in message', text, i);
    }
    names.add(name);
    if (parts.length > 2 &&
        const {'plural', 'select', 'selectordinal'}.contains(parts[1].trim())) {
      // `selector{sub-message}` pairs after the second comma; recurse into each.
      final cases = parts.skip(2).join(',');
      var j = 0;
      while (j < cases.length) {
        if (cases[j] == '{') {
          final end = _closingBrace(cases, j);
          _collectArguments(cases.substring(j + 1, end), names);
          j = end + 1;
        } else {
          j++;
        }
      }
    }
    i = close + 1;
  }
}

/// Placeholder metadata that disagrees with the message: an argument the
/// message uses with no `@key.placeholders` entry, an entry the message never
/// uses, or an entry with no `type`. gen-l10n would infer a type for the first
/// and ship code that compiles; the convention is that the metadata says it.
List<String> placeholderDrift(Map<String, dynamic> arb) {
  final problems = <String>[];
  for (final key in messageKeys(arb)) {
    final value = arb[key];
    if (value is! String) {
      problems.add('$key: message value is not a string');
      continue;
    }
    final Set<String> used;
    try {
      used = icuArguments(value);
    } on FormatException catch (error) {
      problems.add('$key: ${error.message}');
      continue;
    }
    final meta = arb['@$key'];
    final declared = meta is Map ? meta['placeholders'] : null;
    final entries = declared is Map ? declared : const <String, dynamic>{};
    for (final name in used) {
      if (!entries.containsKey(name)) {
        problems.add('$key: uses {$name} but @$key.placeholders has no $name');
      }
    }
    for (final entry in entries.entries) {
      final name = entry.key as String;
      if (!used.contains(name)) {
        problems.add(
          '$key: @$key declares placeholder $name the message never uses',
        );
        continue;
      }
      final type = entry.value is Map ? (entry.value as Map)['type'] : null;
      if (type is! String || type.trim().isEmpty) {
        problems.add('$key: @$key.placeholders.$name has no type');
      }
    }
  }
  return problems;
}

void main() {
  group('app_en.arb follows the key conventions', () {
    late Map<String, dynamic> arb;
    setUpAll(() => arb = _enArb());

    test('has the messages these checks read', () {
      expect(messageKeys(arb).length, greaterThan(1000));
    });

    test('every key is lowerCamelCase', () {
      expect(badKeyNames(arb), isEmpty);
    });

    test('every key has an @key block with a non-empty description', () {
      expect(missingDescriptions(arb), isEmpty);
    });

    test('no @key metadata is orphaned', () {
      expect(orphanMetadata(arb), isEmpty);
    });

    test('placeholders are named and typed, and used', () {
      expect(placeholderDrift(arb), isEmpty);
    });
  });

  group('the checks fail on what they are for', () {
    test('a key that is not lowerCamelCase is named', () {
      final bad = badKeyNames({
        'SettingsFooBar': 'x',
        'settings_foo': 'x',
        'settings.foo': 'x',
        'settings foo': 'x',
        '1settings': 'x',
        'settingsFoo2': 'x',
        '@@locale': 'en',
        '@settingsFoo2': <String, dynamic>{},
      });
      expect(bad.map((p) => p.split(':').first), [
        'SettingsFooBar',
        'settings_foo',
        'settings.foo',
        'settings foo',
        '1settings',
      ]);
    });

    test('a key with no metadata block is named', () {
      final arb = {
        'settingsFooBar': 'Foo',
        'settingsOk': 'Ok',
        '@settingsOk': {'description': 'Fine.'},
      };
      expect(missingDescriptions(arb), [
        'settingsFooBar: no @settingsFooBar metadata block',
      ]);
    });

    test('an empty, blank, missing or non-string description is named', () {
      final arb = {
        'a': 'x',
        '@a': {'description': ''},
        'b': 'x',
        '@b': {'description': '   '},
        'c': 'x',
        '@c': <String, dynamic>{},
        'd': 'x',
        '@d': {'description': 7},
        'e': 'x',
        '@e': 'not a map',
        'f': 'x',
        '@f': {'description': 'Fine.'},
      };
      expect(missingDescriptions(arb).map((p) => p.split(':').first), [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
    });

    test('orphan metadata is named; @@globals are not metadata', () {
      final arb = {
        '@@locale': 'en',
        'kept': 'x',
        '@kept': {'description': 'Fine.'},
        '@gone': {'description': 'Its message was deleted.'},
      };
      expect(orphanMetadata(arb), [
        '@gone: metadata for a message key that does not exist',
      ]);
    });

    test('an argument with no placeholders entry is named', () {
      final arb = {
        'greeting': 'Hello {name}',
        '@greeting': {'description': 'Fine.'},
      };
      expect(placeholderDrift(arb), [
        'greeting: uses {name} but @greeting.placeholders has no name',
      ]);
    });

    test('a plural, select and nested argument each need an entry', () {
      final arb = {
        'summary':
            '{count, plural, =0{None} =1{One} other{{count} in {where}}} '
            '{kind, select, a{{who}} other{x}}',
        '@summary': {
          'description': 'Fine.',
          'placeholders': {
            'count': {'type': 'num'},
          },
        },
      };
      expect(placeholderDrift(arb)..sort(), [
        'summary: uses {kind} but @summary.placeholders has no kind',
        'summary: uses {where} but @summary.placeholders has no where',
        'summary: uses {who} but @summary.placeholders has no who',
      ]);
    });

    test('a declared placeholder the message never uses is named', () {
      final arb = {
        'plain': 'No arguments here',
        '@plain': {
          'description': 'Fine.',
          'placeholders': {
            'stale': {'type': 'String'},
          },
        },
      };
      expect(placeholderDrift(arb), [
        'plain: @plain declares placeholder stale the message never uses',
      ]);
    });

    test('a placeholder with no type is named', () {
      final arb = {
        'preview': 'Preview: {text}',
        '@preview': {
          'description': 'Fine.',
          'placeholders': {'text': <String, dynamic>{}},
        },
      };
      expect(placeholderDrift(arb), [
        'preview: @preview.placeholders.text has no type',
      ]);
    });

    test('an unmatched opening brace is reported, not crashed on', () {
      final arb = {
        'broken': 'Hello {name',
        '@broken': {'description': 'Fine.'},
      };
      expect(placeholderDrift(arb).single, startsWith('broken: '));
    });

    test('clean metadata passes', () {
      final arb = {
        'count': '{n, plural, =1{1 item} other{{n} items}}',
        '@count': {
          'description': 'Fine.',
          'placeholders': {
            'n': {'type': 'int'},
          },
        },
        'when': 'On {date}',
        '@when': {
          'description': 'Fine.',
          'placeholders': {
            'date': {'type': 'DateTime', 'format': 'yMd'},
          },
        },
      };
      expect(placeholderDrift(arb), isEmpty);
      expect(missingDescriptions(arb), isEmpty);
      expect(badKeyNames(arb), isEmpty);
    });
  });

  group('icuArguments', () {
    test('finds simple, repeated and whitespace-padded arguments', () {
      expect(icuArguments('A {x} and {x} and { y }'), {'x', 'y'});
      expect(icuArguments('No arguments'), isEmpty);
      expect(icuArguments(''), isEmpty);
    });

    test('reads plural, select and selectordinal, including nesting', () {
      expect(
        icuArguments('{n, plural, =0{No {thing}} one{# {thing}} other{{n}}}'),
        {'n', 'thing'},
      );
      expect(icuArguments('{who, select, male{{a}} female{{b}} other{{c}}}'), {
        'who',
        'a',
        'b',
        'c',
      });
      expect(
        icuArguments('{rank, selectordinal, one{{rank}st} other{{rank}th}}'),
        {'rank'},
      );
    });

    test('counts a formatted argument by its name only', () {
      expect(icuArguments('{when, date, yMd} {amount, number, compact}'), {
        'when',
        'amount',
      });
    });

    test('treats an apostrophe as an ordinary character', () {
      expect(icuArguments("Don't show {count} of {total}'s"), {
        'count',
        'total',
      });
    });

    test('rejects an argument with no name', () {
      expect(() => icuArguments('Hello {}'), throwsFormatException);
      expect(
        () => icuArguments('Hello { , plural, other{x}}'),
        throwsFormatException,
      );
    });

    test('does not check a stray closing brace', () {
      // Deliberate (see the doc comment): pinned so tightening it is a choice.
      expect(icuArguments('Total } {n}'), {'n'});
      expect(icuArguments('{n} }'), {'n'});
    });

    test('rejects an unmatched opening brace', () {
      expect(() => icuArguments('Hello {name'), throwsFormatException);
      expect(
        () => icuArguments('{n, plural, other{{n} items}'),
        throwsFormatException,
      );
    });
  });
}
