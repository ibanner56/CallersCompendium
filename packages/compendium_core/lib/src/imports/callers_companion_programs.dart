import 'package:meta/meta.dart';

import '../model/program.dart';
import '../util/uuid.dart';
import 'callers_companion_usr_archive.dart';
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
/// rows, resolving each item's CC dance reference to an already-committed
/// Compendium dance id via [danceIdByCcRowId].
///
/// This is a **pure builder** — it takes no repository and performs no I/O,
/// mirroring [mapCallersCompanionDance]'s philosophy — so it is trivially
/// unit-testable and stays Flutter-free in the core. The app layer calls it
/// *after* the dance import commits (so [danceIdByCcRowId] maps CC `Dance`
/// record ids → the new Compendium dance ids), then persists the returned
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
    final title = _titleFor(set);

    final (eventDate, dateIssue) = _parseEventDate(set.eventDate, set.recordId);
    if (dateIssue != null) issues.add(dateIssue);

    final slots = <ProgramSlot>[];
    var position = 0;
    for (final item in set.items) {
      String? danceId;
      String? text;
      if (item.danceRecordId != null) {
        danceId = danceIdByCcRowId[item.danceRecordId];
        if (danceId == null) {
          // The referenced dance was not imported/committed; keep the slot as
          // a placeholder text note rather than dropping it silently.
          text = (item.breakText ?? '').trim().isNotEmpty
              ? item.breakText!.trim()
              : 'Dance not imported (Caller\'s Companion dance '
                    '#${item.danceRecordId})';
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
        text = (item.breakText ?? '').trim().isEmpty
            ? null
            : item.breakText!.trim();
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
          guestCaller: (item.guestCaller ?? '').trim().isEmpty
              ? null
              : item.guestCaller!.trim(),
          plannedMinutes: item.minutes,
        ),
      );
    }

    programs.add(
      Program(
        id: mintId(),
        title: title,
        eventDate: eventDate,
        venue: _clean(set.location),
        band: _clean(set.band),
        caller: _clean(set.caller),
        dancerLevel: _clean(set.dancerLevel),
        notes: _clean(set.notes) ?? '',
        slots: slots,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  return CcProgramsResult(programs: programs, issues: issues);
}

String _titleFor(CcSet set) {
  final title = (set.title ?? '').trim();
  if (title.isNotEmpty) return title;
  final date = (set.eventDate ?? '').trim();
  if (date.isNotEmpty) return "Caller's Companion set — $date";
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

String? _clean(String? raw) {
  final v = raw?.trim() ?? '';
  return v.isEmpty ? null : v;
}
