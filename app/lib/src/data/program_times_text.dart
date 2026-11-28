import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../editor/program_times.dart';
import '../export/export_labels_l10n.dart';
import 'regional_formats.dart';

/// The time the program editor's time picker opens at for a time not yet
/// set: 7:30 pm, a common start for an evening dance.
const int kDefaultPickerMinute = 19 * 60 + 30;

/// The editor label for [field], such as "Start time" or "Arrive by".
String programTimeFieldLabel(AppLocalizations l10n, ProgramTimeField field) =>
    switch (field) {
      ProgramTimeField.start => l10n.programsStartTimeLabel,
      ProgramTimeField.end => l10n.programsEndTimeLabel,
      ProgramTimeField.lesson => l10n.programsLessonTimeLabel,
      ProgramTimeField.arrival => l10n.programsArrivalTimeLabel,
    };

/// The program summary's times line (#2350), such as
/// "Lesson 7:00 PM · Dance 7:30 PM–10:30 PM · Arrive by 6:30 PM", or `null`
/// when the program has no times. Empty times are left out. The dance's own
/// times are phrased as the set-list text and PDF phrase them
/// ([programDanceTimes]), including "(next day)".
///
/// Unlike the set-list text and PDF, this includes Arrive by: the summary is
/// the caller's own screen. [use24Hour] is the device's clock
/// ([formatTimeOfDay]).
String? programTimesSummary(
  Program program,
  AppLocalizations l10n, {
  required bool use24Hour,
}) {
  String format(int minute) =>
      formatTimeOfDay(minute, l10n, use24Hour: use24Hour);
  final dance = programDanceTimes(
    program,
    formatTime: format,
    labels: programExportLabels(l10n),
  );
  final parts = [
    if (program.lessonMinute case final lesson?)
      l10n.programsSummaryLessonTime(format(lesson)),
    ?(dance == null ? null : l10n.programsSummaryDanceTime(dance)),
    if (program.arrivalMinute case final arrival?)
      l10n.programsSummaryArriveBy(format(arrival)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
