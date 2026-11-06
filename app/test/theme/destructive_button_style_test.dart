import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/destructive_button_style.dart';
import 'package:compendium_app/src/theme/wcag.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
    ('highContrast', AppTheme.highContrast),
  ]) {
    test('a destructive confirm is error-filled with onError text ($name)', () {
      final scheme = theme.colorScheme;
      final style = destructiveFilledButtonStyle(scheme);
      expect(style.backgroundColor!.resolve(<WidgetState>{}), scheme.error);
      expect(style.foregroundColor!.resolve(<WidgetState>{}), scheme.onError);
    });

    // palette_contrast_test.dart covers the gallery palettes; this covers the
    // three default themes, so every bundled theme keeps the label readable.
    test('the destructive label clears AA text contrast ($name)', () {
      final scheme = theme.colorScheme;
      expect(
        Wcag.contrastRatio(scheme.onError, scheme.error),
        greaterThanOrEqualTo(Wcag.aaText),
      );
    });

    // The red-text variant (D-1) sits on the dialog surface, not on its own
    // fill, so its contrast is error against that surface.
    test('the red text button clears AA on the dialog surface ($name)', () {
      final scheme = theme.colorScheme;
      expect(
        destructiveTextButtonStyle(
          scheme,
        ).foregroundColor!.resolve(<WidgetState>{}),
        scheme.error,
      );
      expect(
        Wcag.contrastRatio(
          scheme.error,
          theme.dialogTheme.backgroundColor ?? scheme.surfaceContainerHigh,
        ),
        greaterThanOrEqualTo(Wcag.aaText),
      );
    });
  }
}
