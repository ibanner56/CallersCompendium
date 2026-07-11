import 'package:flutter/material.dart';

void main() {
  runApp(const CompendiumApp());
}

/// Root widget. Real navigation shell arrives with Phase 3; this placeholder
/// exists so the scaffold builds and boots on every platform.
class CompendiumApp extends StatelessWidget {
  const CompendiumApp({super.key});

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
      home: const Scaffold(body: Center(child: Text("Caller's Compendium"))),
    );
  }
}
