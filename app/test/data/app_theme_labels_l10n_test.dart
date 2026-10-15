import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/app_theme_labels_l10n.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_theme.dart';

/// The resolvers switch on stable keys with an English fallback, so a typo in a
/// key would silently render English. Japanese shares no word with the English
/// fallbacks, which makes "still equals the English label" a reliable signal
/// that a case was missed.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ja = lookupAppLocalizations(const Locale('ja'));

  test('English resolves to the stable English labels', () {
    for (final g in AppThemeGroup.values) {
      expect(appThemeGroupLabel(en, g), g.label);
    }
    for (final s in AppThemeSelection.values) {
      expect(appThemeLabel(en, s), s.label, reason: s.name);
    }
    for (final g in CustomThemeRoles.groups) {
      expect(themeEditorGroupLabel(en, g), g.label);
    }
    for (final r in CustomThemeRoles.all) {
      expect(themeEditorRoleLabel(en, r), r.label, reason: r.key);
    }
    for (final p in CustomThemeRoles.allPairs) {
      expect(themeEditorPairLabel(en, p), p.label, reason: p.foreground);
    }
  });

  test('every group, generic name, role and pair is translated', () {
    for (final g in AppThemeGroup.values) {
      expect(appThemeGroupLabel(ja, g), isNot(g.label), reason: g.name);
    }
    for (final s in const [
      AppThemeSelection.system,
      AppThemeSelection.light,
      AppThemeSelection.dark,
      AppThemeSelection.softDark,
      AppThemeSelection.highContrast,
    ]) {
      expect(appThemeLabel(ja, s), isNot(s.label), reason: s.name);
    }
    for (final g in CustomThemeRoles.groups) {
      expect(themeEditorGroupLabel(ja, g), isNot(g.label), reason: g.label);
    }
    for (final r in CustomThemeRoles.all) {
      expect(themeEditorRoleLabel(ja, r), isNot(r.label), reason: r.key);
    }
    for (final p in CustomThemeRoles.allPairs) {
      expect(themeEditorPairLabel(ja, p), isNot(p.label), reason: p.foreground);
    }
  });

  test('brand palette names stay literal in every locale', () {
    expect(
      appThemeLabel(ja, AppThemeSelection.catppuccinFrappe),
      'Catppuccin Frappé',
    );
    expect(appThemeLabel(ja, AppThemeSelection.dracula), 'Dracula');
  });

  test('every theme has a description in a non-English locale', () {
    for (final s in AppThemeSelection.values) {
      expect(appThemeDescription(ja, s), isNotEmpty, reason: s.name);
      expect(
        appThemeDescription(ja, s),
        isNot(appThemeDescription(en, s)),
        reason: s.name,
      );
    }
  });
}
