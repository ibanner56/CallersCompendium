import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A Settings row whose control is a [DropdownButton].
///
/// `ListTile.trailing` is never wrapped and gives its child no bounded width, so
/// an intrinsically wide dropdown steals the title's width at larger text sizes
/// (overflow in debug, a zero-width title in release). Where there is room this
/// renders the familiar `ListTile(trailing: dropdown)`; where there is not it
/// renders the `ListTile` and puts the dropdown, expanded to the full width, on
/// its own line below the label.
///
/// [dropdownBuilder] receives `expanded`, which the caller must forward to
/// `DropdownButton.isExpanded`; every other property of the dropdown (key,
/// value, items, onChanged) stays with the caller.
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
