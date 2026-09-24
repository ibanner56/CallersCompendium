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

  testWidgets(
    'narrow layout: adding three tags in a row keeps the picker open each '
    'time (#894 — the count matters, since a fix that only reopens once '
    'passes a two-addition test for the wrong reason)',
    (tester) async {
      final added = <String>[];
      await setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: NamePicker(
              fieldKey: 'tag',
              selectedIds: const [],
              namesById: const {},
              options: const [
                (id: 'red', name: 'Red'),
                (id: 'blue', name: 'Blue'),
                (id: 'green', name: 'Green'),
              ],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: (name) async => name,
              sheetSemanticLabel: 'Tags',
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('tag-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      for (final tag in ['red', 'blue', 'green']) {
        expect(
          find.byType(BottomSheet),
          findsOneWidget,
          reason: 'sheet must still be open before picking "$tag"',
        );
        await tester.enterText(find.byKey(const ValueKey('tag-input')), tag);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('tag-option-$tag')));
        await tester.pumpAndSettle();
      }

      expect(added, ['red', 'blue', 'green']);
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'sheet must still be open after the third tag',
      );
    },
  );

  group('canonical equivalence', _canonicalEquivalenceGroup);
}

// ---------------------------------------------------------------------------
// The picker's "is this name new?" test must ask the same question the
// repository will ask, or it offers a create the repository then refuses.
//
// Found in review on #1410: the comparison was `toLowerCase()` on raw text,
// while `ChoreographerRepository` looks the incumbent up by
// `normalizeShareableText`, which composes to NFC. With a live "café", typing
// the decomposed form matched nothing here, offered "create", and threw
// `DuplicateNaturalKeyError` out of `onSelected` — an async callback nothing
// awaits — so the author was silently not created. The PR body had claimed this
// path was unreachable; it was not.
//
// Both halves are asserted, because fixing only the exact test would suppress
// "create" while the substring filter still failed to show the row it collides
// with, leaving an empty list and no way forward.

/// "café" composed: U+00E9.
const _nfcCafe = 'caf\u00e9';

/// "café" decomposed: "e" + U+0301 combining acute.
const _nfdCafe = 'cafe\u0301';

void _canonicalEquivalenceGroup() {
  Future<List<String>> pumpAndType(
    WidgetTester tester,
    String typed, {
    required List<NameOption> options,
  }) async {
    final created = <String>[];
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: NamePicker(
            fieldKey: 'author',
            selectedIds: const [],
            namesById: const {},
            options: options,
            onAdd: (_) {},
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
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('author-input')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('author-input')), typed);
    await tester.pumpAndSettle();
    return created;
  }

  testWidgets('a decomposed spelling of a live name offers no create', (
    tester,
  ) async {
    // Precondition: the two strings really are canonically equivalent and not
    // byte-equal, or the test passes without exercising anything.
    expect(_nfcCafe == _nfdCafe, isFalse);
    expect(_nfcCafe.toLowerCase() == _nfdCafe.toLowerCase(), isFalse);

    await pumpAndType(
      tester,
      _nfdCafe,
      options: const [(id: 'c1', name: _nfcCafe)],
    );

    expect(
      find.byKey(ValueKey('author-option-create:$_nfdCafe')),
      findsNothing,
      reason: 'the repository would refuse this create',
    );
    expect(
      find.byKey(const ValueKey('author-option-c1')),
      findsOneWidget,
      reason: 'the incumbent must still be offered, or there is no way forward',
    );
  });

  testWidgets('a genuinely new name still offers create', (tester) async {
    // The other side of the guard: a comparison widened until it matches
    // everything would pass the test above and break the picker.
    await pumpAndType(
      tester,
      'Brand New Author',
      options: const [(id: 'c1', name: _nfcCafe)],
    );
    expect(
      find.byKey(const ValueKey('author-option-create:Brand New Author')),
      findsOneWidget,
    );
  });

  testWidgets('case-only difference still offers no create, as before', (
    tester,
  ) async {
    // Pre-existing behaviour this change must not disturb: the picker was
    // already case-insensitive, and `naturalKeyMatchKey` keeps it so.
    await pumpAndType(
      tester,
      'GENE HUBERT',
      options: const [(id: 'gene', name: 'Gene Hubert')],
    );
    expect(
      find.byKey(const ValueKey('author-option-create:GENE HUBERT')),
      findsNothing,
    );
  });
}
