import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import 'src/data/active_dialect_scope.dart';
import 'src/data/app_database.dart';
import 'src/data/app_theme_scope.dart';
import 'src/data/custom_themes_controller.dart';
import 'src/data/custom_themes_scope.dart';
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
  late final CustomThemesController _customThemes;

  @override
  void initState() {
    super.initState();
    _appData = AppData(openAppDatabase());
    _customThemes = CustomThemesController(_appData.repositories.settings);
    _bootstrap = _startupSequence();
  }

  Future<void> _startupSequence() async {
    await _appData.repositories.ensureMigrated();
    await _appData.repositories.dances.purgeDeleted(
      now: DateTime.now().toUtc(),
    );
    // Load the persisted dialect, defaulting to Larks/Robins when unset.
    // Stored as a full dialect JSON (custom dialects supported); older builds
    // stored just a preset name, which we still resolve.
    final stored = await _appData.repositories.settings.get(kActiveDialectKey);
    final dialect = dialectFromStored(stored);
    if (dialect != null) _dialectNotifier.value = dialect;
    // Load the persisted theme selection, defaulting to System when unset.
    final themeName =
        await _appData.repositories.settings.get(kAppThemeKey) as String?;
    final selection = AppThemeSelection.forName(themeName);
    if (selection != null) _themeNotifier.value = selection;
    // Load any locally-saved custom themes and the active one (if set).
    await _customThemes.load();
  }

  @override
  void dispose() {
    _dialectNotifier.dispose();
    _themeNotifier.dispose();
    _customThemes.dispose();
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
    // The theme depends on two sources — the built-in selection and the active
    // custom theme — and both are MaterialApp properties, so the MaterialApp
    // must rebuild when either changes.
    return ListenableBuilder(
      listenable: Listenable.merge([_themeNotifier, _customThemes]),
      builder: (context, _) {
        final selection = _themeNotifier.value;
        final activeCustom = _customThemes.active;
        // Wiring cases (`ux-modernization.md` §4 / §4A / §4B):
        //  • custom active — a locally-saved custom theme wins over the
        //                    built-in selection; pin its scheme into both slots.
        //  • system        — follow the OS via themeMode, Hearth light/dark.
        //  • highContrast  — force the outline-driven HC theme into both slots.
        //  • pinned        — any other built-in selection pins one concrete
        //                    scheme into both slots.
        final ThemeData lightTheme;
        final ThemeData darkTheme;
        final ThemeMode themeMode;
        if (activeCustom != null) {
          final pinned = AppTheme.fromScheme(activeCustom.toScheme());
          lightTheme = pinned;
          darkTheme = pinned;
          themeMode = activeCustom.themeMode;
        } else {
          themeMode = selection.themeMode;
          if (selection == AppThemeSelection.system) {
            lightTheme = AppTheme.light;
            darkTheme = AppTheme.dark;
          } else if (selection.isHighContrast) {
            lightTheme = AppTheme.highContrast;
            darkTheme = AppTheme.highContrast;
          } else {
            final pinned = AppTheme.fromScheme(selection.scheme!);
            lightTheme = pinned;
            darkTheme = pinned;
          }
        }

        return MaterialApp(
          title: "Caller's Compendium",
          theme: lightTheme,
          darkTheme: darkTheme,
          highContrastTheme: AppTheme.highContrast,
          highContrastDarkTheme: AppTheme.highContrast,
          themeMode: themeMode,
          builder: (context, child) => RepositoriesScope(
            repositories: _appData.repositories,
            child: AppThemeScope(
              notifier: _themeNotifier,
              child: CustomThemesScope(
                controller: _customThemes,
                child: ActiveDialectScope(
                  notifier: _dialectNotifier,
                  child: child!,
                ),
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
