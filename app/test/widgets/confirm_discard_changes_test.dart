// Guards the shared "Discard changes?" prompt and back guard (UX2-1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/confirm_discard_changes.dart';

import '../support/l10n_harness.dart';

/// Pumps a button that shows [confirmDiscardChanges] and records the choice.
Future<DiscardChangesChoice? Function()> _pumpPrompt(
  WidgetTester tester, {
  String? saveLabel,
}) async {
  DiscardChangesChoice? choice;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => choice = await confirmDiscardChanges(
              context,
              saveLabel: saveLabel,
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ask'));
  await tester.pumpAndSettle();
  return () => choice;
}

/// Pumps a launcher that pushes a page guarded by [DiscardChangesGuard] with
/// [dirty], and records whether the page has been popped.
Future<bool Function()> _pumpGuarded(
  WidgetTester tester, {
  required bool dirty,
}) async {
  var popped = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DiscardChangesGuard(
                    dirty: dirty,
                    child: Scaffold(
                      appBar: AppBar(title: const Text('editor')),
                    ),
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => popped;
}

void main() {
  group('confirmDiscardChanges', () {
    testWidgets('offers Keep editing and a destructive Discard by default', (
      tester,
    ) async {
      final read = await _pumpPrompt(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('You have unsaved changes.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Keep editing'), findsOneWidget);
      final discard = tester.widget<FilledButton>(
        find.byKey(const ValueKey('discard-confirm')),
      );
      final scheme = Theme.of(
        tester.element(find.byKey(const ValueKey('discard-confirm'))),
      ).colorScheme;
      expect(discard.style?.backgroundColor?.resolve(const {}), scheme.error);
      expect(find.byKey(const ValueKey('discard-save')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(read(), DiscardChangesChoice.discard);
    });

    testWidgets('Keep editing and a tap outside both keep editing', (
      tester,
    ) async {
      var read = await _pumpPrompt(tester);
      await tester.tap(find.byKey(const ValueKey('discard-cancel')));
      await tester.pumpAndSettle();
      expect(read(), DiscardChangesChoice.keepEditing);

      read = await _pumpPrompt(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(read(), DiscardChangesChoice.keepEditing);
    });

    testWidgets('with a save label, Save is the filled action and Discard a '
        'text button', (tester) async {
      final read = await _pumpPrompt(tester, saveLabel: 'Save and exit');
      expect(
        tester.widget(find.byKey(const ValueKey('discard-confirm'))),
        isA<TextButton>(),
      );
      expect(
        tester.widget(find.byKey(const ValueKey('discard-save'))),
        isA<FilledButton>(),
      );
      await tester.tap(find.text('Save and exit'));
      await tester.pumpAndSettle();
      expect(read(), DiscardChangesChoice.save);
    });
  });

  group('DiscardChangesGuard', () {
    testWidgets('a clean page leaves on Back without asking', (tester) async {
      final popped = await _pumpGuarded(tester, dirty: false);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(popped(), isTrue);
    });

    testWidgets('a dirty page asks on Back; Keep editing stays', (
      tester,
    ) async {
      final popped = await _pumpGuarded(tester, dirty: true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('discard-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsOneWidget);
      expect(popped(), isFalse);
    });

    testWidgets('a dirty page asks on the back arrow; Discard leaves', (
      tester,
    ) async {
      final popped = await _pumpGuarded(tester, dirty: true);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsNothing);
      expect(popped(), isTrue);
    });
  });
}
