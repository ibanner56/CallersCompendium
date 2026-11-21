import 'package:compendium_core/compendium_core.dart';

import 'display_defaults.dart' show kDefaultProgramCallerKey;

/// Resolves the host-caller filter for the derived calling-history queries
/// (issue #583), given the live "Track calling history for all callers" toggle
/// ([trackAllCallers], read from [TrackHistoryForAllCallersScope]) and the
/// persisted default caller ([kDefaultProgramCallerKey]).
///
/// Returns:
/// * `null` — "track all callers" (the historical behavior) — when
///   [trackAllCallers] is `true`, or when no default caller is configured
///   (absent/blank), or on a settings read failure (fail-open so history is
///   never silently over-filtered).
/// * the trimmed default-caller name otherwise, to be passed as `callerFilter`
///   to `CollectionData.watch` / `CollectionData.load` (which hand it to
///   `ProgramRepository.programDerivedCounts`) and to
///   `ProgramRepository.watchCallingHistoryForDance`; the repository folds it
///   with `LOWER(TRIM(...))` for a trim + case-insensitive match.
///
/// Caller reads [trackAllCallers] from the scope synchronously (before any
/// `await`) and passes it here. Pass [defaultCaller] — the live value from
/// `DefaultProgramCallerScope.maybeOf` — when the caller has it: it is used
/// instead of reading the setting, which a just-edited value may not have
/// reached yet (the handler flips the notifier before it persists). `null`
/// reads the default caller from settings.
Future<String?> resolveCallingHistoryCallerFilter(
  SettingsRepository settings, {
  required bool trackAllCallers,
  String? defaultCaller,
}) async {
  if (trackAllCallers) return null;
  if (defaultCaller != null) {
    return normalizeCallingHistoryCaller(defaultCaller);
  }
  Object? stored;
  try {
    stored = await settings.get(kDefaultProgramCallerKey);
  } catch (_) {
    // diagnostics: silent — a settings read failure must not over-filter history;
    // falls back to tracking all callers (fail-open, no user surface).
    return null;
  }
  final caller = stored is String ? stored.trim() : '';
  return caller.isEmpty ? null : caller;
}
