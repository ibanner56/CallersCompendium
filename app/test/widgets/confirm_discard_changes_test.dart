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
    testWidgets('Keep editing is the filled action and Discard a red text '
        'button (D-1)', (tester) async {
      final read = await _pumpPrompt(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('You have unsaved changes.'), findsOneWidget);
      expect(find.byKey(const ValueKey('discard-save')), findsNothing);

      // The safe choice is the primary one; Discard must never be filled.
      expect(
        tester.widget(find.byKey(const ValueKey('discard-cancel'))),
        isA<FilledButton>(),
      );
      final discard = find.byKey(const ValueKey('discard-confirm'));
      expect(tester.widget(discard), isA<TextButton>());
      expect(tester.widget(discard), isNot(isA<FilledButton>()));
      final scheme = Theme.of(tester.element(discard)).colorScheme;
      expect(
        (tester.widget<TextButton>(
          discard,
        )).style?.foregroundColor?.resolve(const {}),
        scheme.error,
      );

      await tester.tap(discard);
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

    testWidgets('with a save label, Save is the filled action, Exit without '
        'saving a red text button and Cancel a plain one', (tester) async {
      final read = await _pumpPrompt(tester, saveLabel: 'Save and exit');
      final discard = find.byKey(const ValueKey('discard-confirm'));
      expect(tester.widget(discard), isA<TextButton>());
      expect(tester.widget(discard), isNot(isA<FilledButton>()));
      final scheme = Theme.of(tester.element(discard)).colorScheme;
      expect(
        tester
            .widget<TextButton>(discard)
            .style
            ?.foregroundColor
            ?.resolve(const {}),
        scheme.error,
      );
      final cancel = tester.widget<TextButton>(
        find.byKey(const ValueKey('discard-cancel')),
      );
      expect(cancel.style?.foregroundColor, isNull);
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
