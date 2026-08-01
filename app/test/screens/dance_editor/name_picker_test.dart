import 'package:compendium_app/src/screens/dance_editor/name_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/l10n_harness.dart';
import '../../support/screen_size.dart';

void main() {
  testWidgets(
    'narrow layout: creating a brand-new author from the sheet attaches it, '
    'closes, and the re-opened sheet (from the refocus-to-add-another loop) '
    'starts with an empty query, above a simulated keyboard',
    (tester) async {
      final added = <String>[];
      final created = <String>[];
      await setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: NamePicker(
              fieldKey: 'author',
              selectedIds: const [],
              namesById: const {},
              options: const [(id: 'gene', name: 'Gene Hubert')],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: (name) async {
                created.add(name);
                return 'new-id';
              },
              sheetSemanticLabel: 'Authors',
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('author-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Simulate a software keyboard inset, as issue #716 describes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('author-input')),
        'Brand New Author',
      );
      await tester.pumpAndSettle();

      final createOption = find.byKey(
        const ValueKey('author-option-create:Brand New Author'),
      );
      expect(createOption, findsOneWidget);
      final optionRect = tester.getRect(createOption);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

      await tester.tap(createOption);
      await tester.pumpAndSettle();

      expect(created, ['Brand New Author']);
      expect(added, ['new-id']);
      // The existing clear+refocus-on-select behavior (issue #402) reopens
      // the sheet on narrow layouts too, so a second add can start straight
      // away — and it must start from an empty query, not the previous
      // typed text.
      expect(find.byType(BottomSheet), findsOneWidget);
      final reopenedField = tester.widget<TextField>(
        find.byKey(const ValueKey('author-input')),
      );
      expect(reopenedField.controller?.text, isEmpty);
    },
  );

  testWidgets(
    'narrow layout: attaching an existing author closes the sheet without '
    'creating',
    (tester) async {
      final added = <String>[];
      final created = <String>[];
      await setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: NamePicker(
              fieldKey: 'author',
              selectedIds: const [],
              namesById: const {},
              options: const [(id: 'gene', name: 'Gene Hubert')],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: (name) async {
                created.add(name);
                return 'new-id';
              },
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('author-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('author-input')),
        'Gene',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('author-option-gene')));
      await tester.pumpAndSettle();

      expect(added, ['gene']);
      expect(created, isEmpty);
    },
  );
}
