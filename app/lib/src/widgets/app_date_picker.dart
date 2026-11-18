import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';

/// Flutter's date picker, opened the way Flutter's own date-picker helper
/// opens it but with the app's dialog motion and sizing.
///
/// That helper takes no [AnimationStyle], so the dialog it opens would still
/// animate with the in-app Reduce motion switch on. This builds the same
/// [DatePickerDialog] and opens it through [showDialog] with
/// [AppMotion.styleFor], and with [uncappedDialogBuilder] so the picker can
/// grow with the text scale. Use it instead of the helper everywhere in the
/// app; `app_motion_test.dart` checks that.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialDate,
}) {
  final locale = DatePickerTheme.of(context).locale;
  return showDialog<DateTime>(
    context: context,
    animationStyle: AppMotion.styleFor(context),
    builder: (context) {
      Widget dialog = DatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
      if (locale != null) {
        dialog = Localizations.override(
          context: context,
          locale: locale,
          child: dialog,
        );
      }
      return uncappedDialogBuilder(context, dialog);
    },
  );
}
