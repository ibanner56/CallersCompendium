/// Which keyboard-shortcut vocabulary a tooltip should use.
library;

import 'package:flutter/material.dart';

/// The `platform` argument of the shortcut-hint tooltips in the ARB: `apple`
/// where shortcuts use Command (macOS, and iPadOS with a keyboard), `other`
/// everywhere else. Follows the ambient [Theme] platform, as the navigation
/// rail's search hint does, so a platform override in a test or preview
/// reaches the tooltip too.
String shortcutPlatform(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.macOS || platform == TargetPlatform.iOS
      ? 'apple'
      : 'other';
}
