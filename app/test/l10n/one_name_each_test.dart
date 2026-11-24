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
    // One name for the user's own figures. The feature is "Custom Figures",
    // one of them is "your figure"; "combination", "new figure" and "term"
    // name the three kinds only. "your own figures" (plural) and
    // "No custom figures yet" stay, as the 2026-10-29 decision kept them.
    RegExp(r'[Ff]igures? of your own|[Ff]igure of yours'): 'your figure(s)',
    RegExp(r'[Yy]our own figure\b(?!s)'): 'your figure',
    RegExp(r'[Yy]our new figures'): 'your figures',
    RegExp(r'[Yy]our combinations?'): 'your figures',
    RegExp(r'^Your figures'): 'Custom Figures',
    // Library means everything (collection, programs, settings); collection
    // means dances only. A header must not call a subset the library.
    RegExp(r'^Library$'): 'Dances',
    RegExp(r'Caller.s Companion library file'): 'Caller\'s Companion data file',
    // One name for Perform mode.
    RegExp(r'Perform view|program Perform|individual Perform'): 'Perform mode',
    RegExp(r'^Performance$'): 'Perform mode',
    // Cancel abandons a dialog, Not now defers an offer, Dismiss hides a
    // banner.
    RegExp(r'^(Later|Decide later)$'): 'Cancel, Not now or Dismiss',
    // One name for repeating an action.
    RegExp(r'\b[Rr]etry\b'): 'Try again',
    // One phrase for irreversibility, one arrow for menu paths.
    RegExp(r'\b[Cc]annot be undone'): "This can't be undone.",
    RegExp(
      r'\b(Settings|General|Defaults|Program|Appearance|Dialect|Experimental)\s*[›→>]',
    ): 'Settings ▸ …',
    // Required fields are not starred; only optional ones say "(optional)".
    RegExp(r'\s\*$'): 'no asterisk (the validator explains it)',
    // Errors: "Couldn't", no "Please", no "Something went wrong", and no
    // internals in the main sentence.
    RegExp(r'\b[Cc]ould not\b'): "Couldn't",
    RegExp(r'\bPlease\b'): 'no "Please"',
    RegExp(r'[Ss]omething went wrong'): 'what could not be done',
    RegExp(r'HTTP status|[Uu]navailable dance|\{bytes\}|\btaxonomy\b'):
        'plain words; keep detail in a secondary line',
    RegExp(r'integrity check'): 'safety check',
  };

  // Retired wordings that must still be caught: each must match its own
  // pattern, so a pattern can't rot into one that never fires.
  const retiredExamples = <String>[
    'Recently Deleted',
    'Deleted items',
    'Trash',
    'performance view',
    'Choreographer',
    'note / waltz',
    'a custom figure',
    'Re-check custom figures',
    'Your own figure',
    'a figure of your own',
    'This figure of yours is gone',
    'Shorthands for your new figures',
    'one of your combinations',
    'Your figures',
    "Your figures' defaults",
    'Library',
    "This isn't a Caller's Companion library file",
    "Used only in this program's Perform view",
    'Show caller notes in program Perform',
    'Show timer for individual Perform',
    'Performance',
    'Later',
    'Decide later',
    'Retry',
    'This cannot be undone.',
    'go to Settings › General',
    'Settings ▸ Defaults › Shared dance fields',
    'show them again in Settings → Defaults',
    'Title *',
    'Could not save the program.',
    'Please try again.',
    'Something went wrong here',
    'The server answered with HTTP status {code}.',
    'Unavailable dance ({id})',
    'File ready ({bytes} bytes).',
    'This move is no longer in the taxonomy.',
    'A database integrity check failed.',
  ];

  // `customFiguresEmptyTitle` ("No custom figures yet") names the user's own
  // library, which D-3 option (a) leaves as it is.
  const allowedKeys = {'customFiguresEmptyTitle'};

  // "&" and "+" belong in names and fixed labels where space is short, and in
  // text the user types. Everything else says "and". Keys kept, with why.
  const symbolAllowed = <String, String>{
    'settingsLanguageRegionTitle': 'fixed heading',
    'settingsGeneralBackupRestoreHeader': 'fixed heading',
    'settingsDialectDanceDetailsHeader': 'fixed heading',
    'themeEditorGroupSurfaceText': 'fixed heading',
    'themeEditorGroupOutlineEffects': 'fixed heading',
    'settingsUpdatesDownloadTitle': 'fixed label',
    'updateBannerDownloadInstall': 'button, short space',
    'migrationBelowFloorBackUpAndReset': 'button, short space',
    'customFiguresEmpty': 'names the + button',
    'settingsDefaultsFreeTextEntrySubtitle': 'example of typed text',
    'danceEditorFiguresHelpFreeText': 'example of typed text',
    'danceEditorTypeFigureHelper': 'example of typed text',
    'figureTextSheetHelp': 'example of typed text',
    'figureTextSheetHelpDropsLabels': 'example of typed text',
  };

  test('app_en.arb says "and" in running text, not "&" or "+"', () {
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final offenders = <String>[];
    arb.forEach((key, value) {
      if (key.startsWith('@') || value is! String) return;
      if (symbolAllowed.containsKey(key)) return;
      if (RegExp(r' [&+] ').hasMatch(value)) offenders.add('$key: "$value"');
    });
    expect(offenders, isEmpty);
  });

  test('every symbolAllowed key still has an "&" or "+" to allow', () {
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    for (final key in symbolAllowed.keys) {
      expect(
        RegExp(r' [&+] ').hasMatch(arb[key] as String),
        isTrue,
        reason: '$key no longer has an "&" or "+": drop it from the list',
      );
    }
  });

  test('every retired pattern matches a known retired wording', () {
    for (final pattern in retired.keys) {
      expect(
        retiredExamples.any(pattern.hasMatch),
        isTrue,
        reason: 'no example of a retired wording matches $pattern',
      );
    }
  });

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
