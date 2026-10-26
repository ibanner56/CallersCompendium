import 'package:flutter/material.dart';

/// Corner-radius / shape tokens (§1d): 8 / 12 / 16, dialogs 28.
class AppShapes {
  const AppShapes._();

  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double radiusDialog = 28;

  static const BorderRadius borderRadiusSmall = BorderRadius.all(
    Radius.circular(radiusSmall),
  );
  static const BorderRadius borderRadiusMedium = BorderRadius.all(
    Radius.circular(radiusMedium),
  );
  static const BorderRadius borderRadiusLarge = BorderRadius.all(
    Radius.circular(radiusLarge),
  );

  static const RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: borderRadiusMedium,
  );
  static const RoundedRectangleBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusDialog)),
  );

  /// Dialog size bounds. Flutter's default sets only a 280 minimum, so an
  /// AlertDialog with a long body stretched to nearly the full width of a
  /// desktop window and read as one or two very long lines. 560 is the M3
  /// dialog maximum, and the cap the app's own sized dialogs already used.
  static const BoxConstraints dialogConstraints = BoxConstraints(
    minWidth: 280,
    maxWidth: 560,
  );
}

/// The `builder:` for Flutter's own date picker. It sizes itself from the text
/// scale (496dp wide at 1×, wider as text grows), so [AppShapes.dialogConstraints]
/// would crowd it from about 1.15× up. This lifts the cap for that one dialog.
Widget uncappedDialogBuilder(BuildContext context, Widget? child) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(
      dialogTheme: theme.dialogTheme.copyWith(
        constraints: const BoxConstraints(minWidth: 280),
      ),
    ),
    child: child!,
  );
}
