// A dedicated screen hosting the program-matrix column editor (issue #935,
// Phase 3). The editor lists ~100 columns, so it lives on its own page — pushed
// from the Program settings pane, mirroring the "Manage venues" entry point —
// rather than nested inside the settings list, where a large reorderable list
// inside another scrollable breaks layout and semantics.
import 'package:compendium_core/compendium_core.dart' show MatrixColumnConfig;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/program_matrix_column_config_scope.dart';
import '../../data/repositories_scope.dart';
import 'matrix_column_editor.dart';
import 'settings_keys.dart';

/// Full-page host for [MatrixColumnEditor]. Reads the live column config and the
/// active dialect from their scopes, and on every edit flips the live notifier
/// (so an open program matrix rebuilds immediately) then persists the new config
/// under [kProgramMatrixColumnsKey].
class MatrixColumnEditorScreen extends StatelessWidget {
  const MatrixColumnEditorScreen({super.key});

  Future<void> _persist(BuildContext context, MatrixColumnConfig config) async {
    ProgramMatrixColumnConfigScope.notifierOf(context).value = config;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kProgramMatrixColumnsKey, config.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsMatrixColumnsHeader)),
      body: SafeArea(
        child: MatrixColumnEditor(
          config: ProgramMatrixColumnConfigScope.of(context),
          dialect: ActiveDialectScope.of(context),
          onConfigChanged: (config) => _persist(context, config),
        ),
      ),
    );
  }
}
