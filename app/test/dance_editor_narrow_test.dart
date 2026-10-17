import 'dart:io';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Registers the bundled font files under the family names the theme uses, so
/// text is measured with real glyph widths instead of the test font's
/// full-em boxes.
Future<void> _loadBundledFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }

  await load('AtkinsonHyperlegible', [
    'AtkinsonHyperlegible-Regular.ttf',
    'AtkinsonHyperlegible-Bold.ttf',
  ]);
  await load('Roboto', ['Roboto-VariableFont.ttf']);
  await load('Fraunces', ['Fraunces-VariableFont.ttf']);
}

void main() {
  // #1868: the Ahem test font overflowed the formation dropdown by 152px; with
  // the real fonts only the Progression dropdown (half a row) overflows.
  testWidgets('dance editor form fits at 360dp with real fonts', (
    tester,
  ) async {
    await _loadBundledFonts();
    final repos = openTestRepositories();
    await tester.binding.setSurfaceSize(const Size(360, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        theme: AppTheme.light,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const DanceEditorScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('formation-field')), findsOneWidget);
    // A RenderFlex overflow is reported as a framework exception.
    expect(tester.takeException(), isNull);
  });
}
