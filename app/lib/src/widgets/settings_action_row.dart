import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A Settings row whose control is a labelled button (Import…, Restore, …).
///
/// `ListTile.trailing` is never wrapped, so a button with a long label (the
/// German and Danish ones are) takes its natural width from the row and leaves
/// the title a sliver — at 2× text, a few pixels. Where there is room this
/// renders the familiar `ListTile(trailing: button)`; where there is not it
/// renders the `ListTile` and puts the button on its own line below the text,
/// aligned to the row's trailing edge. Same shape as [SettingsDropdownRow].
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.title,
    required this.subtitle,
    required this.button,
    this.tileKey,
    super.key,
  });

  /// The row is inline when the available width is at least this many logical
  /// pixels per unit of text scale. A labelled button is roughly 140–220px wide
  /// in the shipped languages, so below this it would take well over 40% of the
  /// row and starve the title; phones (360) always stack, tablets and desktop
  /// stay inline until text is enlarged.
  static const double inlineWidthPerTextScale = 480;

  final Widget title;
  final Widget subtitle;

  /// The button, built once: it is placed either in the trailing slot or below
  /// the text.
  final Widget button;

  /// Key for the underlying [ListTile], for tests that inspect it.
  final Key? tileKey;

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
            isThreeLine: true,
            trailing: button,
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
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: button,
              ),
            ),
          ],
        );
      },
    );
  }
}
