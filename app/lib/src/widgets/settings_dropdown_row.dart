import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_dropdown_field.dart';

/// A Settings row whose control is a compact [AppDropdownField].
///
/// `ListTile.trailing` is never wrapped and gives its child no bounded width, so
/// an intrinsically wide dropdown steals the title's width at larger text sizes
/// (overflow in debug, a zero-width title in release). Where there is room this
/// renders the familiar `ListTile(trailing: dropdown)`; where there is not it
/// renders the `ListTile` and puts the dropdown, expanded to the full width, on
/// its own line below the label.
///
/// [dropdownBuilder] receives `expanded`, which the caller must forward to
/// [AppDropdownField.fillWidth] (with [AppDropdownField.compact] set); every
/// other property of the dropdown (key, value, entries, onChanged) stays with
/// the caller.
class SettingsDropdownRow extends StatelessWidget {
  const SettingsDropdownRow({
    required this.title,
    required this.dropdownBuilder,
    this.subtitle,
    this.isThreeLine = false,
    this.tileKey,
    super.key,
  });

  /// The row is inline when the available width is at least this many logical
  /// pixels per unit of text scale; below that the dropdown moves under the
  /// label. Scaling keeps the same text-to-space ratio at every system size.
  /// 360 is the width of an ordinary phone, so at the default text size a short
  /// dropdown stays inline there and rows only stack once text is enlarged or
  /// the surface is narrower than a phone.
  static const double inlineWidthPerTextScale = 360;

  /// Above this text scale the dropdown always has its own line, however wide
  /// the surface: a list tile's trailing slot is at most 56 dp tall (48 dp at
  /// a desktop's compact density), and one line of the dropdown's value is
  /// 48 dp at twice the default size, so it outgrows the slot beyond that.
  static const double maxInlineTextScale = 2;

  final Widget title;
  final Widget? subtitle;

  /// Reserve three lines for the title and subtitle in the inline layout. The
  /// wrapped layout never needs it: the dropdown has its own line.
  final bool isThreeLine;

  /// Key for the underlying [ListTile], for tests that inspect it.
  final Key? tileKey;

  final Widget Function(bool expanded) dropdownBuilder;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            scale <= maxInlineTextScale &&
            constraints.maxWidth >=
                inlineWidthPerTextScale * (scale < 1 ? 1 : scale);
        if (inline) {
          return ListTile(
            key: tileKey,
            title: title,
            subtitle: subtitle,
            isThreeLine: isThreeLine,
            trailing: dropdownBuilder(false),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(key: tileKey, title: title, subtitle: subtitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: dropdownBuilder(true),
            ),
          ],
        );
      },
    );
  }
}
