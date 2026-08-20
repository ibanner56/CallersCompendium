// Part of the Settings screen, split by section. The Program section gathers
// the program-facing preferences — venues, the programming matrix, Perform
// mode, and calling history — that previously lived under General (issue #935).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'matrix_column_editor_screen.dart';
import 'settings_keys.dart';
import '../../data/matrix_collision_mode_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/require_performed_for_history_scope.dart';
import '../../data/track_history_for_all_callers_scope.dart';
import '../../data/venue_entity_mode_scope.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/section_header.dart';
import '../venue_manager_screen.dart';

/// The Program settings section: preferences that shape how programs are built,
/// checked, and performed — the reusable-venues toggle plus the venue manager,
/// the programming-matrix collision mode, the Perform auto-size toggle, and the
/// calling-history rules. Owns the auto-size lazy read and its load-race guard.
///
/// This is the home later phases attach the matrix column editor to (issue
/// #935). Every moved toggle keeps its original widget key and semantics — only
/// its location changed, not its behaviour.
class ProgramSection extends StatefulWidget {
  const ProgramSection({super.key});

  @override
  State<ProgramSection> createState() => _ProgramSectionState();
}

class _ProgramSectionState extends State<ProgramSection> {
  /// Auto-size Perform cards (ROADMAP G.1). Loaded from settings on first build;
  /// defaults on until loaded. `null` = not yet loaded.
  bool? _autoSizePerform;
  bool _autoSizeRequested = false;
  bool _autoSizeUserSet = false;

  /// Lazily loads the persisted auto-size preference the first time this section
  /// is built (avoids reading settings in `initState`). A late read must not
  /// clobber a selection the user made before it resolved.
  void _ensureAutoSizeLoaded(BuildContext context) {
    if (_autoSizeRequested) return;
    _autoSizeRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kAutoSizePerformKey)
        .then((value) {
          // Don't overwrite a selection the user made before the read resolved.
          if (!mounted || _autoSizeUserSet) return;
          setState(() => _autoSizePerform = value is bool ? value : true);
        })
        .catchError((_) {
          // diagnostics: silent — auto-size setting read failed; falls back to on-by-default.
          if (!mounted || _autoSizeUserSet) return;
          setState(() => _autoSizePerform = true);
        });
  }

  Future<void> _onAutoSizeChanged(bool value) async {
    setState(() {
      _autoSizeUserSet = true;
      _autoSizePerform = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kAutoSizePerformKey, value);
  }

  /// Opens the venue manager (browse/create/edit/delete reusable venues).
  Future<void> _onManageVenues() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const VenueManagerScreen()));
  }

  Future<void> _onVenueEntityModeChanged(bool value) async {
    // Same instant-notifier-then-persist pattern: flip the live notifier so an
    // open program editor swaps its venue field/picker immediately, then
    // persist in the background. The toggle is entry/display-mode only — both
    // Program.venue and Program.venueId persist independently, so flipping it
    // never clears the other mode's value.
    VenueEntityModeScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kVenueEntityModeKey, value);
  }

  Future<void> _onMatrixExactBeatCollisionChanged(bool value) async {
    // Same instant-notifier-then-persist pattern: flip the live notifier so an
    // open program's Matrix tab re-evaluates its same-figure collision check
    // immediately (issue #962), then persist in the background.
    MatrixCollisionModeScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kMatrixExactBeatCollisionKey, value);
  }

  Future<void> _onRequirePerformedForHistoryChanged(bool value) async {
    // Same instant-notifier-then-persist pattern as dialect/theme: flip the
    // live notifier so every dependent (including an open dance-detail screen)
    // rebuilds immediately, then persist in the background.
    RequirePerformedForHistoryScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kRequirePerformedForHistoryKey, value);
  }

  Future<void> _onTrackHistoryForAllCallersChanged(bool value) async {
    // Same instant-notifier-then-persist pattern: flip the live notifier so
    // every dependent (an open Collection list or dance-detail screen)
    // re-derives its scoped calling history/counts immediately, then persist.
    TrackHistoryForAllCallersScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kTrackHistoryForAllCallersKey, value);
  }

  Future<void> _onConfigureMatrixColumns() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MatrixColumnEditorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureAutoSizeLoaded(context);
    return _ProgramView(
      venueEntityMode: VenueEntityModeScope.of(context),
      onVenueEntityModeChanged: _onVenueEntityModeChanged,
      onManageVenues: _onManageVenues,
      matrixExactBeatCollision: MatrixCollisionModeScope.of(context),
      onMatrixExactBeatCollisionChanged: _onMatrixExactBeatCollisionChanged,
      onConfigureMatrixColumns: _onConfigureMatrixColumns,
      autoSizePerform: _autoSizePerform ?? true,
      onAutoSizeChanged: _onAutoSizeChanged,
      requirePerformedForHistory: RequirePerformedForHistoryScope.of(context),
      onRequirePerformedForHistoryChanged: _onRequirePerformedForHistoryChanged,
      trackHistoryForAllCallers: TrackHistoryForAllCallersScope.of(context),
      onTrackHistoryForAllCallersChanged: _onTrackHistoryForAllCallersChanged,
    );
  }
}

/// The Program section's controls, grouped by subsection (Venues, Programs,
/// Performance, Calling history). Pure presentation — its parent owns the
/// notifiers and persistence.
class _ProgramView extends StatelessWidget {
  const _ProgramView({
    required this.venueEntityMode,
    required this.onVenueEntityModeChanged,
    required this.onManageVenues,
    required this.matrixExactBeatCollision,
    required this.onMatrixExactBeatCollisionChanged,
    required this.onConfigureMatrixColumns,
    required this.autoSizePerform,
    required this.onAutoSizeChanged,
    required this.requirePerformedForHistory,
    required this.onRequirePerformedForHistoryChanged,
    required this.trackHistoryForAllCallers,
    required this.onTrackHistoryForAllCallersChanged,
  });

  final bool venueEntityMode;
  final ValueChanged<bool> onVenueEntityModeChanged;

  /// Opens the venue manager screen.
  final Future<void> Function() onManageVenues;

  /// The Programs "flag exact beat overlap only" matrix-collision toggle
  /// (issue #962). On by default.
  final bool matrixExactBeatCollision;
  final ValueChanged<bool> onMatrixExactBeatCollisionChanged;

  /// Opens the program-matrix column editor screen (issue #935).
  final Future<void> Function() onConfigureMatrixColumns;

  final bool autoSizePerform;
  final ValueChanged<bool> onAutoSizeChanged;

  final bool requirePerformedForHistory;
  final ValueChanged<bool> onRequirePerformedForHistoryChanged;
  final bool trackHistoryForAllCallers;
  final ValueChanged<bool> onTrackHistoryForAllCallersChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      keyboardDismissBehavior: kTextEntryKeyboardDismiss,
      children: [
        SectionHeader(title: l10n.settingsGeneralVenuesHeader),
        SwitchListTile(
          key: const ValueKey('general-venue-entity-mode'),
          value: venueEntityMode,
          onChanged: onVenueEntityModeChanged,
          title: Text(l10n.settingsGeneralVenueEntityModeTitle),
          subtitle: Text(l10n.settingsGeneralVenueEntityModeSubtitle),
          isThreeLine: true,
        ),
        ListTile(
          key: const ValueKey('general-manage-venues'),
          leading: const Icon(Icons.place_outlined),
          title: Text(l10n.settingsGeneralManageVenuesTitle),
          subtitle: Text(l10n.settingsGeneralManageVenuesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onManageVenues,
        ),
        SectionHeader(title: l10n.settingsGeneralProgramsHeader),
        SwitchListTile(
          key: const ValueKey('general-matrix-exact-beat-collision'),
          value: matrixExactBeatCollision,
          onChanged: onMatrixExactBeatCollisionChanged,
          title: Text(l10n.settingsGeneralMatrixExactCollisionTitle),
          subtitle: Text(l10n.settingsGeneralMatrixExactCollisionSubtitle),
          isThreeLine: true,
        ),
        ListTile(
          key: const ValueKey('program-configure-matrix-columns'),
          leading: const Icon(Icons.view_column_outlined),
          title: Text(l10n.settingsMatrixColumnsHeader),
          subtitle: Text(l10n.settingsMatrixColumnsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onConfigureMatrixColumns,
        ),
        SectionHeader(title: l10n.settingsGeneralPerformanceHeader),
        SwitchListTile(
          key: const ValueKey('settings-auto-size-perform'),
          title: Text(l10n.settingsGeneralAutoSizePerformTitle),
          subtitle: Text(l10n.settingsGeneralAutoSizePerformSubtitle),
          value: autoSizePerform,
          onChanged: onAutoSizeChanged,
        ),
        SectionHeader(title: l10n.settingsGeneralCallingHistoryHeader),
        SwitchListTile(
          key: const ValueKey('general-require-performed-for-history'),
          value: requirePerformedForHistory,
          onChanged: onRequirePerformedForHistoryChanged,
          title: Text(l10n.settingsGeneralRequirePerformedForHistoryTitle),
          subtitle: Text(
            l10n.settingsGeneralRequirePerformedForHistorySubtitle,
          ),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-track-history-for-all-callers'),
          value: trackHistoryForAllCallers,
          onChanged: onTrackHistoryForAllCallersChanged,
          title: Text(l10n.settingsGeneralTrackHistoryForAllCallersTitle),
          subtitle: Text(l10n.settingsGeneralTrackHistoryForAllCallersSubtitle),
          isThreeLine: true,
        ),
      ],
    );
  }
}
