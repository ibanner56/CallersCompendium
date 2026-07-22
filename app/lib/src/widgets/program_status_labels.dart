import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';

/// Localized label for a [ProgramStatus] shown on the status chip and the
/// editor's status picker.
///
/// [ProgramStatus] is defined in the Flutter-free `compendium_core` package
/// (ADR-001), so it cannot carry an `AppLocalizations`-aware label itself; UI
/// routes through this app-side helper instead (mirroring the
/// `collection_query_labels.dart` pattern from the Collection screens).
String programStatusLabel(AppLocalizations l10n, ProgramStatus status) =>
    switch (status) {
      ProgramStatus.draft => l10n.programsStatusDraft,
      ProgramStatus.finalized => l10n.programsStatusFinalized,
      ProgramStatus.performed => l10n.programsStatusPerformed,
    };
