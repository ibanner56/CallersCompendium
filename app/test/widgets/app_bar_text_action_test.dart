import 'dart:io';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/widgets/app_bar_text_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// An [AppBar] action that is a word while it fits and an icon when it
/// doesn't, so a toolbar never overflows at a large text size on a phone.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required Widget action,
    Locale locale = const Locale('en'),
    double width = 320,
    double scale = 2,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('A title long enough to need ellipsizing'),
            actions: [action],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a label that fits is a word', (tester) async {
    await pumpBar(
      tester,
      width: 800,
      scale: 1,
      action: AppBarTextAction(
        label: 'Save',
        icon: Icons.check,
        onPressed: () {},
      ),
    );
    expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a label that does not fit is an icon, named by its label', (
    tester,
  ) async {
    var pressed = 0;
    await pumpBar(
      tester,
      action: AppBarTextAction(
        label: 'Enregistrer',
        icon: Icons.check,
        onPressed: () => pressed++,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byTooltip('Enregistrer'), findsOneWidget);
    // A screen reader announces an icon button by its tooltip.
    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.byIcon(Icons.check),
          matching: find.byType(IconButton),
        ),
      ),
      isSemantics(tooltip: 'Enregistrer', isButton: true),
    );
    await tester.tap(find.byIcon(Icons.check));
    expect(pressed, 1);
  });

  testWidgets('busy shows progress, disabled, and keeps its name', (
    tester,
  ) async {
    await pumpBar(
      tester,
      width: 800,
      scale: 1,
      action: AppBarTextAction(
        label: 'Import',
        icon: Icons.download_done,
        busy: true,
        onPressed: () {},
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Import'), findsNothing);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(find.bySemanticsLabel('Import'), findsOneWidget);
  });

  // Every label an AppBar action carries, in every shipped language, at 2x
  // on a 320px phone beside a back button and a long title.
  final labels = <String, String Function(AppLocalizations)>{
    'commonSave': (l) => l.commonSave,
    'importAction': (l) => l.importAction,
    'userFigureSwitchAction': (l) => l.userFigureSwitchAction,
  };
  for (final locale in AppLocalizations.supportedLocales) {
    for (final MapEntry(key: key, value: label) in labels.entries) {
      testWidgets('$key in $locale fits at 2x on a 320px phone', (
        tester,
      ) async {
        final text = label(lookupAppLocalizations(locale));
        await pumpBar(
          tester,
          locale: locale,
          action: AppBarTextAction(
            label: text,
            icon: Icons.check,
            onPressed: () {},
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  // The AppBars that show a text action, as this test reads the source: each
  // uses AppBarTextAction, so none can overflow at a large text size. A new
  // TextButton, FilledButton or OutlinedButton in an AppBar's actions fails
  // here.
  test('no AppBar action is a bare text button', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = _withoutComments(file.readAsStringSync());
      for (final block in appBarActionBlocks(source)) {
        if (RegExp(
          r'\b(TextButton|FilledButton|OutlinedButton)(\.\w+)?\(',
        ).hasMatch(block)) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the scan finds an AppBar action, however it is laid out', () {
    const source = '''
      AppBar(
        title: Text(x),
        actions: [
          IconButton(onPressed: f, icon: Icon(i)),
          TextButton(onPressed: f, child: Text(y)),
        ],
      )
      SliverAppBar(actions: [FilledButton.icon(onPressed: f)])
      SliverAppBar(actions: <Widget>[TextButton(onPressed: f)])
      AppBar(actions: const [OutlinedButton(onPressed: null)])
      AlertDialog(actions: [TextButton(onPressed: f, child: Text(z))])
    ''';
    final blocks = appBarActionBlocks(source);
    expect(blocks, hasLength(4), reason: 'a dialog is not an AppBar');
    expect(blocks[0], contains('TextButton('));
    expect(blocks[1], contains('FilledButton.icon('));
    expect(blocks[2], contains('TextButton('), reason: 'a typed list');
    expect(blocks[3], contains('OutlinedButton('), reason: 'a const list');
  });
}

/// [source] with every comment blanked out, positions kept.
String _withoutComments(String source) => source
    .replaceAllMapped(
      RegExp(r'/\*.*?\*/', dotAll: true),
      (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
    )
    .replaceAllMapped(RegExp(r'//[^\n]*'), (m) => ' ' * m[0]!.length);

/// The text of each `actions: [...]` list whose enclosing call is an
/// `AppBar(` or `SliverAppBar(`, found by walking delimiters rather than lines,
/// so a list spread over many lines is read whole.
List<String> appBarActionBlocks(String source) {
  final blocks = <String>[];
  for (final match in RegExp(
    r'\bactions:\s*(?:const\s+)?(?:<[^>]*>\s*)?\[',
  ).allMatches(source)) {
    // The call this argument belongs to: the nearest unmatched '(' before it.
    var depth = 0;
    var i = match.start - 1;
    for (; i >= 0; i--) {
      final char = source[i];
      if (')]}'.contains(char)) depth++;
      if ('([{'.contains(char)) {
        if (depth == 0) break;
        depth--;
      }
    }
    if (i < 0) continue;
    final callee = RegExp(r'(\w+)\s*$').firstMatch(source.substring(0, i));
    if (callee == null || !callee[1]!.endsWith('AppBar')) continue;
    var brackets = 1;
    var j = match.end;
    while (brackets > 0 && j < source.length) {
      final char = source[j];
      if (char == '[') brackets++;
      if (char == ']') brackets--;
      j++;
    }
    blocks.add(source.substring(match.end, j - 1));
  }
  return blocks;
}
