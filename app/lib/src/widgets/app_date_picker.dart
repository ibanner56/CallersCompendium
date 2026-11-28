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

/// Flutter's time picker, opened like [showAppDatePicker]: the same
/// [TimePickerDialog] Flutter's time-picker helper builds, but through
/// [showDialog] with [AppMotion.styleFor], so it respects the in-app Reduce
/// motion switch, and with [uncappedDialogBuilder] so it can grow with the
/// text scale. Its 12- or 24-hour dial follows the platform setting, as the
/// helper's does, and so does the program time it sets wherever it is shown
/// (`formatTimeOfDay`). Used for a program's times (#2350).
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) => showDialog<TimeOfDay>(
  context: context,
  animationStyle: AppMotion.styleFor(context),
  builder: (context) => uncappedDialogBuilder(
    context,
    TimePickerDialog(initialTime: initialTime, helpText: helpText),
  ),
);
