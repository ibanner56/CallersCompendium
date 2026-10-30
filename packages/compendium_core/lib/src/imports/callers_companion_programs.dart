import 'package:meta/meta.dart';

import '../model/enums.dart';
import '../model/program.dart';
import '../model/provenance.dart';
import '../util/text_sanitizer.dart';
import '../util/uuid.dart';
import 'callers_companion_usr_archive.dart';
import 'program_slot_note.dart';
import 'structured_draft.dart';

/// The result of [buildCcPrograms]: the built [Program]s plus the non-fatal
/// [ImportIssue]s raised while building them.
@immutable
class CcProgramsResult {
  CcProgramsResult({
    List<Program> programs = const [],
    List<ImportIssue> issues = const [],
  }) : programs = List.unmodifiable(programs),
       issues = List.unmodifiable(issues);

  final List<Program> programs;
  final List<ImportIssue> issues;
}

/// Builds [Program]s from a Caller's Companion [CcUsrArchive]'s `Set`/`SetItem`
/// rows, resolving each item's CC dance reference to a local Compendium dance
/// id via [danceIdByCcRowId].
///
/// This is a **pure builder** — it takes no repository and performs no I/O,
/// mirroring [mapCallersCompanionDance]'s philosophy — so it is trivially
/// unit-testable and stays Flutter-free in the core. The app layer calls it
/// *after* the dance import commits (so [danceIdByCcRowId] maps CC `Dance`
/// record ids → the Compendium dance ids the commit wrote, plus dances the
/// review resolved outside the commit: a skipped re-import row's target, or a
/// row already committed through Import and edit), then persists the returned
/// programs via `ProgramRepository` and records them for undo. Wiring that
/// persistence/undo is an app-layer follow-up because [ImportPipeline] is
/// dance-only; keeping this a pure function avoids a large pipeline refactor in
/// this PR (see the PR notes).
///
/// **Parse-never-fails:** an unresolved dance reference, an unparseable event
/// date, or an empty slot degrades to an [ImportIssue] + a graceful fallback
/// (a text slot noting the missing dance, a null date, a skipped empty slot) —
/// never a throw.
CcProgramsResult buildCcPrograms(
  CcUsrArchive archive, {
  required Map<String, String> danceIdByCcRowId,
  String Function()? newId,
  String Function()? newSlotId,
  DateTime? now,
}) {
  final mintId = newId ?? uuidV4;
  final mintSlotId = newSlotId ?? uuidV4;
  final timestamp = now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final issues = <ImportIssue>[];
  final programs = <Program>[];

  for (final set in archive.sets) {
    final (eventDate, dateIssue) = _parseEventDate(set.eventDate, set.recordId);
    if (dateIssue != null) issues.add(dateIssue);
    final title = _titleFor(set, eventDate);
    final keepSlotCallers = _keepsSlotCallers(set);

    final slots = <ProgramSlot>[];
    var position = 0;
    // A dance flagged `Break` puts the break after it and its alternates
    // (#1974), so the slot waits for the next item that is not an alternate.
    var breakPending = false;
    void addBreak() {
      slots.add(
        ProgramSlot(
          id: mintSlotId(),
          position: position++,
          text: Program.breakSlotText,
        ),
      );
      breakPending = false;
    }

    for (final item in set.items) {
      String? danceId;
      String? text;
      final cleanBreakText = _cleanNote(item.breakText);
      if (breakPending && !item.isAlt) {
        // Unless the set already has its own break slot here.
        final isOwnBreak =
            item.danceRecordId == null &&
            cleanBreakText?.trim().toLowerCase() ==
                Program.breakSlotText.toLowerCase();
        if (isOwnBreak) {
          breakPending = false;
        } else {
          addBreak();
        }
      }
      if (item.danceRecordId != null) {
        danceId = danceIdByCcRowId[item.danceRecordId];
        if (danceId == null) {
          // The referenced dance was not imported/committed; keep the slot as
          // a placeholder text note rather than dropping it silently.
          text =
              cleanBreakText ??
              "$kUnresolvedDanceMarkerPrefix"
                  "Caller's Companion dance #${item.danceRecordId})";
          issues.add(
            ImportIssue(
              severity: ImportIssueSeverity.warning,
              code: 'cc_program_unresolved_dance',
              message:
                  'Set "$title" references dance '
                  '#${item.danceRecordId}, which was not imported; kept the '
                  'slot as a text placeholder.',
            ),
          );
        }
      } else {
        text = cleanBreakText;
      }

      if (danceId == null && (text == null || text.isEmpty)) {
        // A slot with neither a dance nor text cannot be represented; skip it.
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'cc_program_empty_slot',
            message: 'Skipped an empty slot in set "$title".',
          ),
        );
        continue;
      }

      slots.add(
        ProgramSlot(
          id: mintSlotId(),
          position: position++,
          danceId: danceId,
          text: text,
          isAlt: item.isAlt,
          guestCaller: keepSlotCallers ? _cleanLine(item.guestCaller) : null,
          danceMinutes: item.minutes,
        ),
      );
      if (item.breakAfter) breakPending = true;
    }
    if (breakPending) addBreak();

    programs.add(
      Program(
        id: mintId(),
        title: title,
        eventDate: eventDate,
        venue: _cleanLine(set.location),
        band: _cleanLine(set.band),
        caller: _cleanLine(set.caller),
        dancerLevel: _cleanLine(set.dancerLevel),
        notes: _cleanNote(set.notes) ?? '',
        hideAlternates: set.hideAlternates,
        slots: slots,
        createdAt: timestamp,
        updatedAt: timestamp,
        // Provenance keyed on the CC `zk_Set_ID` (carried as [CcSet.recordId]),
        // so re-importing the same `.USR` dedupes onto this program instead of
        // creating a duplicate. Mirrors the CC dance provenance stamped by the
        // import pipeline (`source: callersCompanion`, `externalId: zk_*_ID`).
        provenance: Provenance(
          source: ProvenanceSource.callersCompanion,
          externalId: set.recordId,
          importedAt: timestamp,
          sourceVersion: ccUsrSourceVersion,
        ),
      ),
    );
  }

  return CcProgramsResult(programs: programs, issues: issues);
}

/// The program title for [set], dated [eventDate] (its parsed `Date`).
///
/// CC Sets have no title field. CC itself names a set by its
/// `zi_DateLocation_c` calculation, `YYYY/MM/DD - Location`, so the program
/// takes that ("2024/04/20 - NEFFA Contra Party", maintainer decision on
/// #1976): just the date when there is no Location, and just the Location when
/// the date is missing or did not parse.
String _titleFor(CcSet set, DateTime? eventDate) {
  final title = _cleanLine(set.title);
  if (title != null) return title;
  final location = _cleanLine(set.location);
  if (eventDate != null) {
    final y = eventDate.year.toString().padLeft(4, '0');
    final m = eventDate.month.toString().padLeft(2, '0');
    final d = eventDate.day.toString().padLeft(2, '0');
    return location == null ? '$y/$m/$d' : '$y/$m/$d - $location';
  }
  if (location != null) return location;
  final date = _cleanLine(set.eventDate);
  if (date != null) return "Caller's Companion set — $date";
  return "Caller's Companion set #${set.recordId}";
}

/// Whether [set]'s slots keep their `SetItem.Caller` names (#1976).
///
/// CC fills a slot's caller with a first name ("Michael"), the set's own
/// caller's included, so on a set one person called every slot just repeats
/// them. The maintainer's rule (#1976, 2026-10-28, clarified 2026-10-30): keep
/// the slots' callers when they name more than one caller, or when a name is
/// not the set's own caller, matched case-insensitively against the set's
/// `Caller` whole or by its first word. A set with no `Caller` keeps a name, as
/// nothing else records who called.
bool _keepsSlotCallers(CcSet set) {
  final names = <String>{
    for (final item in set.items)
      if (_cleanLine(item.guestCaller) case final name?) _callerKey(name),
  };
  if (names.length > 1) return true;
  if (names.isEmpty) return false;
  final setCaller = _cleanLine(set.caller);
  if (setCaller == null) return true;
  final whole = _callerKey(setCaller);
  final first = whole.split(' ').first;
  return names.single != whole && names.single != first;
}

String _callerKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

(DateTime?, ImportIssue?) _parseEventDate(String? raw, String recordId) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return (null, null);

  // ISO-ish first (what DateTime.tryParse handles).
  final iso = DateTime.tryParse(value);
  if (iso != null) return (DateTime.utc(iso.year, iso.month, iso.day), null);

  // Common US FileMaker shape: M/D/YYYY or M-D-YYYY.
  final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(value);
  if (m != null) {
    var year = int.parse(m.group(3)!);
    if (year < 100) year += year < 70 ? 2000 : 1900;
    final month = int.parse(m.group(1)!);
    final day = int.parse(m.group(2)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      final date = DateTime.utc(year, month, day);
      // DateTime silently normalises impossible dates (e.g. 2/31 → Mar 2), so
      // reject anything that didn't round-trip rather than storing a wrong day.
      if (date.year == year && date.month == month && date.day == day) {
        return (date, null);
      }
    }
  }

  return (
    null,
    ImportIssue(
      severity: ImportIssueSeverity.warning,
      code: 'cc_program_unparsed_date',
      message:
          'Could not parse the event date "$value" for set #$recordId; left '
          'unset.',
    ),
  );
}

/// Sanitizes a single-line imported field (title, venue, band, caller,
/// dancer level, guest caller), stripping control, bidi-override and
/// invisible/format characters plus any embedded tab/newline/CR (issue
/// #444/#611, mirroring `callers_companion_mapping.dart`'s `_sanitizeLine`).
/// Returns null for null/blank/all-stripped input.
String? _cleanLine(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final clean = sanitizeImportedText(trimmed, allowLineBreaks: false).trim();
  return clean.isEmpty ? null : clean;
}

/// Sanitizes a multi-line prose imported field (program notes, break text),
/// stripping control/bidi/format spoofing characters while preserving
/// legitimate newlines (issue #444/#611, mirroring
/// `callers_companion_mapping.dart`'s `_joinNotes`). Returns null for
/// null/blank/all-stripped input.
String? _cleanNote(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final clean = sanitizeImportedText(trimmed).trim();
  return clean.isEmpty ? null : clean;
}
