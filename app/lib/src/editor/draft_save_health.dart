import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Tracks whether an editor's autosave draft is currently failing to write
/// (FAIL-8): a full disk, a locked database, a revoked permission.
///
/// Autosave must never stall editing, so a failed write is not thrown; this is
/// how it becomes visible instead. [failed] drives [DraftNotSavedMarker], and
/// the first failure in a session is logged.
class DraftSaveHealth {
  /// Whether a failure has been logged yet this session. Shared by both
  /// editors: a full disk that breaks one breaks the other, and one record
  /// says so without a flood of identical entries every 500 ms.
  static bool _loggedThisSession = false;

  /// Test hook: forgets that a failure was logged.
  static void resetSessionForTest() => _loggedThisSession = false;

  /// Whether the most recent draft write failed. Cleared by the next write
  /// that succeeds.
  bool failed = false;

  /// Whether the caller should log this failure: true once per session.
  ///
  /// The catch site makes the `logCaughtErrorTypeOnly` call itself, by type
  /// only: the error message could carry the draft's text (CWE-209), and the
  /// type alone tells a disk problem from a codec bug.
  bool claimFirstLog() {
    if (_loggedThisSession) return false;
    return _loggedThisSession = true;
  }

  /// Records a failed draft write; returns whether [failed] changed.
  bool recordFailure() {
    final changed = !failed;
    failed = true;
    return changed;
  }

  /// Records a successful draft write; returns whether [failed] changed.
  bool recordSuccess() {
    final changed = failed;
    failed = false;
    return changed;
  }
}

/// A quiet app-bar marker saying the draft could not be saved. Callers show it
/// only while [DraftSaveHealth.failed].
class DraftNotSavedMarker extends StatelessWidget {
  const DraftNotSavedMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final message = AppLocalizations.of(context).editorDraftNotSaved;
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            Icons.cloud_off_outlined,
            key: const ValueKey('draft-not-saved'),
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}
