import 'package:flutter/material.dart';

import 'src/data/app_database.dart';
import 'src/data/repositories_scope.dart';
import 'src/screens/dance_list_screen.dart';

void main() {
  runApp(const CompendiumApp());
}

/// Root widget. Opens the on-device database once, then hands the
/// [CompendiumRepositories] facade down to the Collection screen via
/// [RepositoriesScope].
class CompendiumApp extends StatefulWidget {
  const CompendiumApp({super.key});

  @override
  State<CompendiumApp> createState() => _CompendiumAppState();
}

class _CompendiumAppState extends State<CompendiumApp> {
  late final AppData _appData;

  @override
  void initState() {
    super.initState();
    _appData = AppData(openAppDatabase());
  }

  @override
  void dispose() {
    _appData.close();
    super.dispose();
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
      home: const DanceListScreen(),
    );
  }
}
