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
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/user_figures_scope.dart';
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
    await persistSetting(
      repos.settings,
      kProgramMatrixColumnsKey,
      config.toJson(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // An Undo of a column delete can run after this screen has closed, so
    // edits persist through the root navigator's context: the app mounts its
    // scopes above the navigator, and that context stays mounted for as long
    // as the app runs. A host that mounts the scopes below the navigator (a
    // focused widget test) keeps this screen's own context.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final appContext =
        ProgramMatrixColumnConfigScope.maybeNotifierOf(rootContext) != null &&
            rootContext.getInheritedWidgetOfExactType<RepositoriesScope>() !=
                null
        ? rootContext
        : context;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsMatrixColumnsHeader)),
      body: SafeArea(
        child: MatrixColumnEditor(
          config: ProgramMatrixColumnConfigScope.of(context),
          dialect: ActiveDialectScope.contraOf(context),
          onConfigChanged: (config) => _persist(appContext, config),
          currentConfig: () =>
              ProgramMatrixColumnConfigScope.maybeNotifierOf(
                appContext,
              )?.value ??
              MatrixColumnConfig.empty,
          userFigures: UserFiguresScope.shownCatalogOf(context),
        ),
      ),
    );
  }
}
