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
}
