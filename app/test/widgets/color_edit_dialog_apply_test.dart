import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_motion.dart';
import 'package:compendium_app/src/widgets/color_edit_dialog.dart';

import '../support/l10n_harness.dart';

/// Opens the dialog from a button and returns a getter for what it popped.
Future<({Color? Function() result, bool Function() closed})> _open(
  WidgetTester tester,
) async {
  Color? result;
  var closed = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<Color>(
                context: context,
                builder: (_) => const ColorEditDialog(
                  title: 'Colour',
                  initial: Color(0xFF804020),
                ),
                animationStyle: AppMotion.styleFor(context),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (result: () => result, closed: () => closed);
}

void main() {
  testWidgets('Apply uses hex text that was typed but not submitted', (
    tester,
  ) async {
    final dialog = await _open(tester);

    // enterText types without pressing Enter, as a caller does before tapping
    // Apply.
    await tester.enterText(find.byType(TextField), '#112233');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(dialog.closed(), isTrue);
    expect(dialog.result(), const Color(0xFF112233));
  });

  testWidgets('Apply accepts hex without the leading hash', (tester) async {
    final dialog = await _open(tester);
    await tester.enterText(find.byType(TextField), 'AbCdEf');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(dialog.result(), const Color(0xFFABCDEF));
  });

  testWidgets('Apply with text that is not a colour stays open and says so', (
    tester,
  ) async {
    final dialog = await _open(tester);
    await tester.enterText(find.byType(TextField), '#12');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(dialog.closed(), isFalse);
    expect(find.byType(ColorEditDialog), findsOneWidget);
    expect(find.text('Enter six hex digits, like #804020.'), findsOneWidget);

    // Correcting the text clears the message and Apply then succeeds.
    await tester.enterText(find.byType(TextField), '#445566');
    await tester.pump();
    expect(find.text('Enter six hex digits, like #804020.'), findsNothing);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(dialog.result(), const Color(0xFF445566));
  });

  testWidgets('Apply without typing returns the opening colour', (
    tester,
  ) async {
    final dialog = await _open(tester);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(dialog.result(), const Color(0xFF804020));
  });
}
