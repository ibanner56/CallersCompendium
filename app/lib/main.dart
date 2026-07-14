import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import 'src/data/active_dialect_scope.dart';
import 'src/data/app_database.dart';
import 'src/data/repositories_scope.dart';
import 'src/screens/app_shell.dart';
import 'src/screens/settings_screen.dart' show kActiveDialectKey;
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
  }

  @override
  void dispose() {
    _dialectNotifier.dispose();
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
    return MaterialApp(
      title: "Caller's Compendium",
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      builder: (context, child) => RepositoriesScope(
        repositories: _appData.repositories,
        child: ActiveDialectScope(notifier: _dialectNotifier, child: child!),
      ),
      home: AppBootstrap(
        future: _bootstrap,
        onRetry: _retry,
        builder: (_) => const AppShell(),
      ),
    );
  }
}
