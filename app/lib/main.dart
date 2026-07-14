import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import 'src/data/active_dialect_scope.dart';
import 'src/data/app_database.dart';
import 'src/data/app_theme_scope.dart';
import 'src/data/repositories_scope.dart';
import 'src/screens/app_shell.dart';
import 'src/screens/settings_screen.dart' show kActiveDialectKey, kAppThemeKey;
import 'src/theme/app_theme.dart';
import 'src/widgets/app_bootstrap.dart';

void main() {
  runApp(const CompendiumApp());
}

/// Root widget. Opens the on-device database once, runs any pending schema
/// migration / derived-index back-fill via
/// [CompendiumRepositories.ensureMigrated] (schema-v2 `dance_figures.section`),
/// then performs a startup purge sweep that hard-deletes soft-deleted dances
/// past the 30-day retention window ([DanceRepository.purgeDeleted]). The app
/// then hands the repositories facade down to the Collection screen via
/// [RepositoriesScope].
///
/// Startup is gated on the migration + purge by [AppBootstrap]: the app shows a
/// loading screen until both complete so no screen reads stale data (an error
/// screen with retry is shown if either fails).
class CompendiumApp extends StatefulWidget {
  const CompendiumApp({super.key});

  @override
  State<CompendiumApp> createState() => _CompendiumAppState();
}

class _CompendiumAppState extends State<CompendiumApp> {
  late final AppData _appData;
  late Future<void> _bootstrap;
  final ValueNotifier<Dialect> _dialectNotifier = ValueNotifier(
    Dialect.larksRobins,
  );
  final ValueNotifier<AppThemeSelection> _themeNotifier = ValueNotifier(
    AppThemeSelection.system,
  );

  @override
  void initState() {
    super.initState();
    _appData = AppData(openAppDatabase());
    _bootstrap = _startupSequence();
  }

  Future<void> _startupSequence() async {
    await _appData.repositories.ensureMigrated();
    await _appData.repositories.dances.purgeDeleted(
      now: DateTime.now().toUtc(),
    );
    // Load the persisted dialect, defaulting to Larks/Robins when unset.
    final name =
        await _appData.repositories.settings.get(kActiveDialectKey) as String?;
    if (name != null) {
      final preset = Dialect.forName(name);
      if (preset != null) _dialectNotifier.value = preset;
    }
    // Load the persisted theme selection, defaulting to System when unset.
    final themeName =
        await _appData.repositories.settings.get(kAppThemeKey) as String?;
    final selection = AppThemeSelection.forName(themeName);
    if (selection != null) _themeNotifier.value = selection;
  }

  @override
  void dispose() {
    _dialectNotifier.dispose();
    _themeNotifier.dispose();
    // dispose() can't be async; explicitly mark the close as fire-and-forget
    // rather than silently dropping an unawaited Future (unawaited_futures).
    unawaited(_appData.close());
    super.dispose();
  }

  void _retry() {
    setState(() => _bootstrap = _startupSequence());
  }

  @override
  Widget build(BuildContext context) {
    // The theme selection is a MaterialApp property (not just inherited state),
    // so the MaterialApp itself must rebuild when it changes.
    return ValueListenableBuilder<AppThemeSelection>(
      valueListenable: _themeNotifier,
      builder: (context, selection, _) {
        // High-contrast is not a ThemeMode; force it into both light and dark
        // slots so it applies regardless of the OS brightness.
        final lightTheme = selection.isHighContrast
            ? AppTheme.highContrast
            : AppTheme.light;
        final darkTheme = selection.isHighContrast
            ? AppTheme.highContrast
            : AppTheme.dark;

        return MaterialApp(
          title: "Caller's Compendium",
          theme: lightTheme,
          darkTheme: darkTheme,
          highContrastTheme: AppTheme.highContrast,
          highContrastDarkTheme: AppTheme.highContrast,
          themeMode: selection.themeMode,
          builder: (context, child) => RepositoriesScope(
            repositories: _appData.repositories,
            child: AppThemeScope(
              notifier: _themeNotifier,
              child: ActiveDialectScope(
                notifier: _dialectNotifier,
                child: child!,
              ),
            ),
          ),
          home: AppBootstrap(
            future: _bootstrap,
            onRetry: _retry,
            builder: (_) => const AppShell(),
          ),
        );
      },
    );
  }
}
