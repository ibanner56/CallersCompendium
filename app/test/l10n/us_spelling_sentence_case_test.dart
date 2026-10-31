import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the D-4 copy rule in `docs/user/style-guide.md` ("App strings"):
/// the English ARB uses US spelling and sentence case.
///
/// Reads `app_en.arb` directly and checks the string values only. Keys,
/// `@key` metadata and the other locales are out of scope: identifiers keep
/// their spelling (`syncConflictFieldColour`), and each locale keeps its own
/// conventions.
Map<String, String> _enStrings() {
  final arb =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final e in arb.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

/// British spellings the app has used, as whole-word patterns. A string that
/// shows text the user types (a search token, a shorthand) is exempt by being
/// listed in [_userTypedKeys]; none needs it today.
final _british = <RegExp>[
  RegExp(r'\bcolou?r\w*', caseSensitive: false), // matched, then filtered below
  RegExp(r'\b(un)?recognis\w*', caseSensitive: false),
  RegExp(r'\bcancell(ed|ing|ation)\b', caseSensitive: false),
  RegExp(
    r'\b(customis|organis|normalis|synchronis|initialis|summaris)\w*',
    caseSensitive: false,
  ),
  RegExp(r'\bgrey\w*', caseSensitive: false),
  RegExp(
    r'\b(centre|behaviour|favour|neighbour|catalogue|programme|labell)\w*',
    caseSensitive: false,
  ),
];

/// Keys whose value is text the user types, so its spelling is theirs.
const _userTypedKeys = <String>{};

/// Capitalized feature and product names. A string made of these is a name,
/// not Title Case, so it is masked before the case check.
const _names = <String>[
  "Caller's Compendium",
  'Caller’s Compendium',
  "Caller's Companion",
  'Caller’s Companion',
  "Caller's Box",
  'Caller’s Box',
  'ContraDB',
  'Device Sync',
  'Custom Figures',
  'Perform',
  'Collection',
  'Programs',
  'Glossary',
  'Becket',
  'English',
];

/// Exact values that read as Title Case but are not.
const _titleCaseOk = <String>{'Yes/No'};

/// macOS menu-bar items follow the platform's Title Case convention (style
/// guide, "App strings"), so the `menu*` keys are exempt from the case check.
bool _isMenuKey(String key) => RegExp(r'^menu[A-Z]').hasMatch(key);

bool _looksTitleCase(String value) {
  if (_titleCaseOk.contains(value)) return false;
  var text = value.replaceAll(RegExp(r'\{[^{}]*\}'), '');
  for (final name in _names) {
    text = text.replaceAll(name, 'x');
  }
  if (RegExp(r'[.!?:;\n]').hasMatch(text)) return false;
  final words = RegExp(
    r"[A-Za-z][A-Za-z'’-]*",
  ).allMatches(text).map((m) => m.group(0)!);
  final rest = words.skip(1).toList();
  // An acronym (JSON, USR, CW) is not a capitalized word.
  final capitalized = rest.where(
    (w) => w[0] == w[0].toUpperCase() && w != w.toUpperCase(),
  );
  return rest.isNotEmpty && capitalized.length == rest.length;
}

void main() {
  final en = _enStrings();

  test('English strings use US spelling', () {
    final hits = <String>[];
    for (final e in en.entries) {
      if (_userTypedKeys.contains(e.key)) continue;
      for (final pattern in _british) {
        for (final m in pattern.allMatches(e.value)) {
          // "color" is the US spelling; only "colour" is British.
          if (m.group(0)!.toLowerCase().startsWith('color')) continue;
          hits.add('${e.key}: "${m.group(0)}"');
        }
      }
    }
    expect(hits, isEmpty, reason: 'use US spelling (docs/user/style-guide.md)');
  });

  test('English strings use sentence case, except macOS menu items', () {
    final hits = <String>[
      for (final e in en.entries)
        if (!_isMenuKey(e.key) && _looksTitleCase(e.value))
          '${e.key}: "${e.value}"',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'capitalize only the first word and proper names '
          '(docs/user/style-guide.md); menu* keys are exempt',
    );
  });

  test('the case check can fail: it flags Title Case and spares names', () {
    expect(_looksTitleCase('Developer Options'), isTrue);
    expect(_looksTitleCase('Back Up + Reset'), isTrue);
    expect(_looksTitleCase('Developer options'), isFalse);
    expect(_looksTitleCase('Turn on Device Sync'), isFalse);
    expect(_looksTitleCase('Export JSON'), isFalse);
    expect(_looksTitleCase('Becket (CCW)'), isFalse);
  });
}
