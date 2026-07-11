import 'dart:async';

import 'package:flutter/material.dart';

import 'src/data/app_database.dart';
import 'src/data/repositories_scope.dart';
import 'src/screens/dance_list_screen.dart';
import 'src/widgets/app_bootstrap.dart';

void main() {
  runApp(const CompendiumApp());
}

/// Root widget. Opens the on-device database once, runs any pending schema
/// migration / derived-index back-fill via
/// [CompendiumRepositories.ensureMigrated] (schema-v2 `dance_figures.section`),
/// then hands the repositories facade down to the Collection screen via
/// [RepositoriesScope].
///
/// Startup is gated on the migration by [AppBootstrap]: the app shows a loading
/// screen until the back-fill completes so no screen reads the derived indexes
/// before they are rebuilt (an error screen with retry is shown if it fails).
class CompendiumApp extends StatefulWidget {
  const CompendiumApp({super.key});

  @override
  State<CompendiumApp> createState() => _CompendiumAppState();
}

class _CompendiumAppState extends State<CompendiumApp> {
  late final AppData _appData;
  late Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _appData = AppData(openAppDatabase());
    _bootstrap = _appData.repositories.ensureMigrated();
  }

  @override
  void dispose() {
    // dispose() can't be async; explicitly mark the close as fire-and-forget
    // rather than silently dropping an unawaited Future (unawaited_futures).
    unawaited(_appData.close());
    super.dispose();
  }

  void _retry() {
    setState(() => _bootstrap = _appData.repositories.ensureMigrated());
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
      builder: (context, child) =>
          RepositoriesScope(repositories: _appData.repositories, child: child!),
      home: AppBootstrap(
        future: _bootstrap,
        onRetry: _retry,
        builder: (_) => const DanceListScreen(),
      ),
    );
  }
}
