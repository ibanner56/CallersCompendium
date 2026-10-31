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
/// date, or an empty slot degrades to a graceful fallback (a text slot or a
/// left-out slot, below; a null date; a skipped empty slot), with an
/// [ImportIssue] where the person should hear of it — never a throw.
///
/// **A dance that did not commit** (maintainer decisions on #1976,
/// 2026-10-30): a slot naming a CC dance [danceIdByCcRowId] does not resolve
/// becomes
/// - nothing, with an info issue, when the dance is not in the file's `Dance`
///   table ([CcUsrArchive.danceRecordIds]): it was deleted in Caller's
///   Companion;
/// - its title then a `Dance not imported (…)` line, with a warning, when it
///   is in [failedCcRowIds]: its commit failed;
/// - its title alone, from [danceTitleByCcRowId], when the import left it out
///   (Skip in review, or an ambiguous row an unattended import skipped);
/// - the `Dance not imported (…)` line alone, with a warning, when there is
///   no title to give.
CcProgramsResult buildCcPrograms(
  CcUsrArchive archive, {
  required Map<String, String> danceIdByCcRowId,
  Map<String, String> danceTitleByCcRowId = const {},
  Set<String> failedCcRowIds = const {},
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
    final title = _titleFor(set);

    final (eventDate, dateIssue) = _parseEventDate(set.eventDate, set.recordId);
    if (dateIssue != null) issues.add(dateIssue);

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

    // A deleted dance's first alternate takes its place (#1976), as removing a
    // slot in the program editor promotes one.
    var promoteAlt = false;
    for (final item in set.items) {
      String? danceId;
      String? text;
      final isAlt = item.isAlt && !promoteAlt;
      promoteAlt = false;
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
      if (item.danceRecordId case final ccId?) {
        danceId = danceIdByCcRowId[ccId];
        final known = archive.danceRecordIds;
        if (danceId == null && known != null && !known.contains(ccId)) {
          // Deleted in Caller's Companion: nothing to show (#1976, 5c). Its
          // break still follows it and its alternates.
          issues.add(
            ImportIssue(
              severity: ImportIssueSeverity.info,
              code: 'cc_program_deleted_dance',
              message:
                  'Set "$title" references dance #$ccId, which is not in the '
                  'file; left the slot out.',
            ),
          );
          if (item.breakAfter) breakPending = true;
          promoteAlt = !item.isAlt;
          continue;
        }
        if (danceId == null) {
          final danceTitle = _cleanLine(danceTitleByCcRowId[ccId]);
          final marker =
              "$kUnresolvedDanceMarkerPrefix"
              "Caller's Companion dance #$ccId)";
          if (cleanBreakText == null &&
              danceTitle != null &&
              !failedCcRowIds.contains(ccId)) {
            // Left out of the import on purpose: the title reads as the slot.
            text = danceTitle;
          } else {
            // The marker sits on its own line, after a blank line, as
            // `danceTitleFromSlotNote` expects. A slot's own text, which a
            // real file never gives a dance slot, wins as before.
            text =
                cleanBreakText ??
                (danceTitle == null ? marker : '$danceTitle\n\n$marker');
            issues.add(
              ImportIssue(
                severity: ImportIssueSeverity.warning,
                code: 'cc_program_unresolved_dance',
                message:
                    'Set "$title" references dance #$ccId, which was not '
                    'imported; kept the slot as a text placeholder.',
              ),
            );
          }
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
          isAlt: isAlt,
          guestCaller: _cleanLine(item.guestCaller),
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

String _titleFor(CcSet set) {
  final title = _cleanLine(set.title);
  if (title != null) return title;
  // CC Sets have no title field; the Location is the de-facto event name.
  final location = _cleanLine(set.location);
  if (location != null) return location;
  final date = _cleanLine(set.eventDate);
  if (date != null) return "Caller's Companion set — $date";
  return "Caller's Companion set #${set.recordId}";
}

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
