import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D-3 (maintainer decision, 2026-10-29): each thing has one name in English.
///
/// Retired variants must not creep back into `app_en.arb`. Only the English
/// template is checked: the other locales are reviewed natively, not matched
/// against these patterns.
void main() {
  // Pattern -> the name that replaces it. Matched, case-sensitively, against
  // every string value (not the `@key` metadata).
  final retired = <RegExp, String>{
    RegExp(r'Recently Deleted'): 'Recently deleted',
    RegExp(r'[Dd]eleted items\b(?<!recently deleted items)'):
        'Recently deleted',
    RegExp(r'\b[Tt]rash\b'): 'Recently deleted',
    RegExp(r'performance view'): 'Perform mode',
    RegExp(r'[Cc]horeographer(?!y)'): 'author',
    RegExp(r'note / waltz'): 'Add note or break',
    // Unparsed text is an "unrecognized figure". Your own figures are
    // "Custom Figures" (the setting) or "your own figures"; the lower-case
    // "custom figure" in the empty states below names that library.
    RegExp(r'a custom figure'): 'an unrecognized figure',
    RegExp(r'(Re-check|Upgrade|Upgraded) custom figures'):
        'unrecognized figures',
  };

  // `customFiguresEmptyTitle` ("No custom figures yet") names the user's own
  // library, which D-3 option (a) leaves as it is.
  const allowedKeys = {'customFiguresEmptyTitle'};

  test('app_en.arb uses one name for each thing (D-3)', () {
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final offenders = <String>[];
    arb.forEach((key, value) {
      if (key.startsWith('@') || value is! String) return;
      if (allowedKeys.contains(key)) return;
      retired.forEach((pattern, use) {
        if (pattern.hasMatch(value)) {
          offenders.add('$key: "$value" — use "$use"');
        }
      });
    });
    expect(offenders, isEmpty);
  });
}
