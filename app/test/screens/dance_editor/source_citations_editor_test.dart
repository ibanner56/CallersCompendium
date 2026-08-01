import 'package:compendium_app/src/screens/dance_editor/source_citations_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/l10n_harness.dart';

/// Sets both the render surface size and the [MediaQuery] physical size to
/// [size]. `setSurfaceSize` alone only affects layout constraints —
/// `MediaQuery.sizeOf`, which `ResponsiveAutocomplete` uses for its
/// breakpoints, reads `FlutterView.physicalSize` instead (see
/// `responsive_autocomplete_test.dart`), so both must be set to faithfully
/// simulate a phone-sized screen in tests.
Future<void> _setScreenSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
}

void main() {
  testWidgets(
    'narrow layout: creating a brand-new source from the sheet attaches it '
    'and closes the sheet, with the create option visible above a '
    'simulated keyboard',
    (tester) async {
      final attached = <String>[];
      final created = <String>[];
      await _setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: SourceCitationsEditor(
              citations: const [],
              sourcesById: const {},
              sourceOptions: [PublishedSource(id: 's1', title: 'CDSS News')],
              onAttach: attached.add,
              onCreate: (title) async {
                created.add(title);
                return 'new-source-id';
              },
              onEditSource: (_) {},
              onRemove: (_) {},
              onChanged: () {},
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('source-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Simulate a software keyboard inset, as issue #716 describes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('source-input')),
        'A Brand New Source',
      );
      await tester.pumpAndSettle();

      final createOption = find.byKey(
        const ValueKey('source-option-create:A Brand New Source'),
      );
      expect(createOption, findsOneWidget);
      final optionRect = tester.getRect(createOption);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

      await tester.tap(createOption);
      await tester.pumpAndSettle();

      expect(created, ['A Brand New Source']);
      expect(attached, ['new-source-id']);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets(
    'narrow layout: attaching an existing source closes the sheet without '
    'creating',
    (tester) async {
      final attached = <String>[];
      final created = <String>[];
      await _setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: SourceCitationsEditor(
              citations: const [],
              sourcesById: const {},
              sourceOptions: [PublishedSource(id: 's1', title: 'CDSS News')],
              onAttach: attached.add,
              onCreate: (title) async {
                created.add(title);
                return 'new-source-id';
              },
              onEditSource: (_) {},
              onRemove: (_) {},
              onChanged: () {},
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('source-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('source-input')),
        'CDSS',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('source-option-s1')));
      await tester.pumpAndSettle();

      expect(attached, ['s1']);
      expect(created, isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );
}
