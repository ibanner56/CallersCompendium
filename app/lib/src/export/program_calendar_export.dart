import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../data/picker_extensions.dart';
import '../data/regional_formats.dart';
import '../widgets/calendar_export_dialogs.dart';
import '../widgets/export_guard.dart';
import '../widgets/program_status_labels.dart';
import 'program_share_bundle.dart' show programShareBundleFileName;
import 'export_labels_l10n.dart';
import 'share_file.dart';
import 'share_sanitization.dart';

export '../widgets/calendar_export_dialogs.dart' show CalendarExportChoice;

/// The MIME type of an iCalendar file.
const calendarMimeType = 'text/calendar';

/// The file extension of an iCalendar file.
const calendarFileExtension = 'ics';

/// The file name for a calendar export of several programs.
const calendarMultiFileName = 'programs.$calendarFileExtension';

/// The Save As filter for an `.ics` file.
@visibleForTesting
XTypeGroup calendarTypeGroup({bool? isLinux}) => XTypeGroup(
  label: 'iCalendar',
  extensions: pickerExtensions([calendarFileExtension], isLinux),
  uniformTypeIdentifiers: const ['com.apple.ical.ics'],
  mimeTypes: const [calendarMimeType],
);

/// The programs the Programs list's "Export calendar" checklist offers,
/// split at [today] (issue #2351).
///
/// * **upcoming** — event date [today] or later, not archived, not in
///   Recently deleted; ticked by default. Soonest first.
/// * **past** — event date before [today], not in Recently deleted; shown only
///   behind "Show past programs", unticked. Most recent first. Archived
///   programs are included here: archiving is what a caller usually does with a
///   gig that has happened, and the caller picks these one by one.
///
/// A program with no event date is in neither: it has no day to put in a
/// calendar. Only the date's year, month and day are compared, as stored
/// (`DateTime.utc(y, m, d)`), against [today]'s local calendar date.
({List<Program> upcoming, List<Program> past}) calendarExportCandidates(
  Iterable<Program> programs,
  DateTime today,
) {
  final todayKey = _dayKey(today);
  final upcoming = <Program>[];
  final past = <Program>[];
  for (final program in programs) {
    final date = program.eventDate;
    if (date == null || program.isDeleted) continue;
    if (_dayKey(date) >= todayKey) {
      if (program.archivedAt == null) upcoming.add(program);
    } else {
      past.add(program);
    }
  }
  int byDate(Program a, Program b) =>
      _dayKey(a.eventDate!).compareTo(_dayKey(b.eventDate!));
  upcoming.sort(byDate);
  past.sort((a, b) => byDate(b, a));
  return (upcoming: upcoming, past: past);
}

int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// The venue record [program] links to, when it resolves.
Venue? _linkedVenue(Program program, Map<String, Venue> venuesById) =>
    switch (program.venueId) {
      final id? => venuesById[id],
      null => null,
    };

/// Whether any of [programs] links a venue with an address, which is what
/// makes the calendar export ask "Include the venue's address".
bool calendarExportNeedsAddressConsent(
  Iterable<Program> programs,
  Map<String, Venue> venuesById,
) => programs.any(
  (p) => switch (_linkedVenue(p, venuesById)) {
    final venue? => venueHasAddress(venue),
    null => false,
  },
);

/// Reduces [program] to what a calendar file may carry (issue #2351).
///
/// The location is built from the venue **after** [sanitizeVenueForShare],
/// never from [Venue.displayName] or `resolveVenueLabel`, which concatenate
/// the postal address unconditionally (#853). Contacts are never offered:
/// `include` is left at its empty default, so all six are cleared. With
/// [includeAddress] the sanitized venue keeps its address and the location is
/// its name followed by its address lines. An unlinked program, or a link that
/// does not resolve, uses the typed venue label as written.
///
/// The program's start and end times (#2350) become a timed event; with no
/// start it stays all-day. [scheduleLine] is the already-formatted lesson,
/// arrival and (with no start) end line ([programCalendarScheduleLine]); the
/// calendar export is the caller's own, so Arrive by is in it (maintainer
/// ruling, #2350).
///
/// Pay, notes, band, caller and slots are not read at all.
ProgramCalendarEvent programCalendarEvent(
  Program program, {
  required Map<String, Venue> venuesById,
  required bool includeAddress,
  required String statusLabel,
  String? scheduleLine,
}) {
  final linked = _linkedVenue(program, venuesById);
  final venue = linked == null
      ? null
      : sanitizeVenueForShare(linked, includeAddress: includeAddress);
  final String? location;
  if (venue != null) {
    final postal = [
      venue.postalCode,
      venue.plus4,
    ].where(_present).map((s) => s!.trim()).join('-');
    location = [
      venue.name,
      venue.address1,
      venue.address2,
      venue.city,
      venue.stateProv,
      postal,
      venue.country,
    ].where(_present).map((s) => s!.trim()).join(', ');
  } else {
    location = program.venue;
  }
  return ProgramCalendarEvent(
    programId: program.id,
    title: program.title,
    date: program.eventDate!,
    updatedAt: program.updatedAt,
    start: _timeOfDay(program.startMinute),
    end: _timeOfDay(program.endMinute),
    location: location,
    statusLabel: statusLabel,
    scheduleLine: scheduleLine,
    venueTime: venue?.time,
  );
}

CalendarTimeOfDay? _timeOfDay(int? minuteOfDay) => minuteOfDay == null
    ? null
    : CalendarTimeOfDay(minuteOfDay ~/ 60, minuteOfDay % 60);

/// The lesson and arrival times, and an end time that has no start, as one
/// line for an event's description, such as "Lesson 7:00 PM · Arrive by
/// 6:30 PM", in the words and clock of the program summary; `null` when none
/// of them is set.
///
/// The end is here only when there is no start: such a program is an all-day
/// event, so without this line ("Dance until 10:30 PM") its end would appear
/// nowhere in the event. With a start, the end is in the event's times.
String? programCalendarScheduleLine(AppLocalizations l10n, Program program) {
  final endOnly = program.startMinute == null
      ? danceTimesText(
          startMinute: null,
          endMinute: program.endMinute,
          formatTime: (m) => formatTimeOfDay(m, l10n),
          labels: programExportLabels(l10n),
        )
      : null;
  final parts = [
    if (program.lessonMinute case final lesson?)
      l10n.programsSummaryLessonTime(formatTimeOfDay(lesson, l10n)),
    ?(endOnly == null ? null : l10n.programsSummaryDanceTime(endOnly)),
    if (program.arrivalMinute case final arrival?)
      l10n.programsSummaryArriveBy(formatTimeOfDay(arrival, l10n)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

bool _present(String? s) => s != null && s.trim().isNotEmpty;

/// The `.ics` text for [programs], each through [programCalendarEvent].
String buildProgramsCalendar(
  AppLocalizations l10n,
  Iterable<Program> programs, {
  required Map<String, Venue> venuesById,
  required bool includeAddress,
  DateTime? now,
}) => programsToICalendar([
  for (final program in programs)
    if (program.eventDate != null)
      programCalendarEvent(
        program,
        venuesById: venuesById,
        includeAddress: includeAddress,
        statusLabel: programStatusLabel(l10n, program.status),
        scheduleLine: programCalendarScheduleLine(l10n, program),
      ),
], now: now ?? clock.now());

/// Opens the Save / Share / Cancel choice for a calendar file.
typedef CalendarChoicePicker =
    Future<CalendarExportChoice?> Function(BuildContext context);

/// Asks whether to include the venue's address: `null` cancels the export.
typedef CalendarAddressConsent = Future<bool?> Function(BuildContext context);

/// Writes [ics] to a temporary `.ics` file for the share sheet.
Future<XFile> writeCalendarTempFile(String ics, String fileName) =>
    writeBundleFile(ics, fileName, mimeType: calendarMimeType);

/// Saves [ics] through the platform's Save As, filtered to `.ics`.
Future<JsonSaveResult?> saveCalendarFile(String ics, String fileName) =>
    saveJsonBundle(
      ics,
      fileName,
      acceptedTypeGroups: [calendarTypeGroup()],
      stageFile: writeCalendarTempFile,
      mobileMimeTypes: const [calendarMimeType],
    );

/// Runs a calendar export: the address consent (when a chosen venue has an
/// address), then the Save / Share / Cancel choice, then the delivery.
///
/// Every field is an optional test seam; the defaults are the production
/// dialogs and platform calls. Modelled on `JsonExportDelivery`, without its
/// Copy choice: a calendar file is for a calendar app, not the clipboard.
class CalendarExportDelivery {
  const CalendarExportDelivery({
    this.addressConsent,
    this.choicePicker,
    this.saveInvoker,
    this.shareInvoker,
    this.fileWriter,
  });

  final CalendarAddressConsent? addressConsent;
  final CalendarChoicePicker? choicePicker;
  final Future<JsonSaveResult?> Function(String ics, String fileName)?
  saveInvoker;
  final Future<void> Function(ShareParams params)? shareInvoker;
  final BundleFileWriter? fileWriter;

  /// Exports [programs] as one `.ics` file named [fileName].
  ///
  /// Nothing is written when the user dismisses either dialog. The address
  /// consent is asked only when [calendarExportNeedsAddressConsent], and its
  /// answer is used for this export alone.
  Future<void> export(
    BuildContext context, {
    required List<Program> programs,
    required Map<String, Venue> venuesById,
    required String fileName,
    required String subject,
    required Rect? sharePositionOrigin,
  }) async {
    var includeAddress = false;
    if (calendarExportNeedsAddressConsent(programs, venuesById)) {
      final consent = await (addressConsent ?? CalendarAddressDialog.show)(
        context,
      );
      if (consent == null || !context.mounted) return;
      includeAddress = consent;
    }
    final choice = await (choicePicker ?? showCalendarExportChoiceDialog)(
      context,
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final ics = buildProgramsCalendar(
      l10n,
      programs,
      venuesById: venuesById,
      includeAddress: includeAddress,
    );
    const source = 'program_calendar_export.export';
    switch (choice) {
      case CalendarExportChoice.save:
        await guardExport(messenger, l10n.exportCalendarSaveError, () async {
          final result = await (saveInvoker ?? saveCalendarFile)(ics, fileName);
          if (result == null) return;
          _announceSaved(messenger, l10n, result);
        }, source: source);
      case CalendarExportChoice.share:
        await guardExport(messenger, l10n.exportCalendarShareError, () async {
          final result = await shareOrSaveBundleFile(
            json: ics,
            fileName: fileName,
            subject: subject,
            origin: sharePositionOrigin,
            shareInvoker: shareInvoker,
            bundleFileWriter: fileWriter ?? writeCalendarTempFile,
            saveInvoker: saveInvoker ?? saveCalendarFile,
          );
          if (result?.saved case final saved?) {
            _announceSaved(messenger, l10n, saved);
          }
        }, source: source);
    }
  }
}

void _announceSaved(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  JsonSaveResult saved,
) {
  final message = saved.fileName == null
      ? l10n.exportCalendarSavedGeneric
      : saved.path.isEmpty
      ? l10n.exportJsonSaved(saved.fileName!)
      : l10n.exportJsonSavedTo(saved.fileName!, saved.path);
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// The file name for a single program's calendar export.
String programCalendarFileName(Program program) => programShareBundleFileName(
  program.title,
  extension: calendarFileExtension,
  eventDate: program.eventDate,
);
