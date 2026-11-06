import 'dart:async';
import 'dart:typed_data';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/calling_card_settings_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:compendium_app/src/screens/settings/calling_card_layout_editor_screen.dart';
import 'package:compendium_app/src/screens/settings/calling_card_section.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/pdf_probe.dart';
import '../support/test_repositories.dart';

/// A 1 × 1 transparent PNG: what the fake rasterizer hands the preview.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _Harness {
  _Harness(this.repos, this.notifier);
  final CompendiumRepositories repos;
  final ValueNotifier<CallingCardSettings> notifier;

  Future<CallingCardSettings> stored() async => CallingCardSettings.fromJson(
    await repos.settings.get(kCallingCardSettingsKey),
  );
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget child, {
  CallingCardSettings settings = CallingCardSettings.defaults,
}) async {
  final repos = openTestRepositories();
  final notifier = ValueNotifier(settings);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: ActiveDialectScope(
        notifier: ValueNotifier(Dialect.larksRobins),
        child: CallingCardSettingsScope(
          notifier: notifier,
          child: MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(repos, notifier);
}

Widget _section() =>
    const Scaffold(body: SingleChildScrollView(child: CallingCardSection()));

void main() {
  group('Experimental › Calling cards', () {
    testWidgets('the switch turns calling cards on and stores it', (
      tester,
    ) async {
      final h = await _pump(tester, _section());
      // Collapsed while calling cards are off, like the Glossary section:
      // its heading opens it.
      expect(find.byKey(const ValueKey('calling-card-enabled')), findsNothing);
      await tester.tap(find.text('Calling cards'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calling-card-enabled')));
      await tester.pumpAndSettle();
      expect(h.notifier.value.enabled, isTrue);
      await tester.runAsync(() async {
        expect((await h.stored()).enabled, isTrue);
      });
    });

    testWidgets('a preset keeps the card\'s orientation', (tester) async {
      final h = await _pump(
        tester,
        _section(),
        settings: const CallingCardSettings(
          enabled: true,
          size: CallingCardSize(3, 5, CallingCardUnit.inch),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('calling-card-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A6 (105 × 148 mm)').last);
      await tester.pumpAndSettle();
      expect(
        h.notifier.value.size,
        const CallingCardSize(105, 148, CallingCardUnit.millimetre),
      );
      await tester.runAsync(() async {
        expect(
          (await h.stored()).size,
          const CallingCardSize(105, 148, CallingCardUnit.millimetre),
        );
      });
    });

    testWidgets('Landscape turns the card', (tester) async {
      final h = await _pump(
        tester,
        _section(),
        settings: const CallingCardSettings(enabled: true),
      );
      await tester.tap(find.byKey(const ValueKey('calling-card-landscape')));
      await tester.pumpAndSettle();
      expect(
        h.notifier.value.size,
        const CallingCardSize(3, 5, CallingCardUnit.inch),
      );
    });

    testWidgets('a custom size is stored only while it is valid', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        _section(),
        settings: const CallingCardSettings(enabled: true),
      );
      await tester.tap(find.byKey(const ValueKey('calling-card-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom size').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('calling-card-width')),
        '5.5',
      );
      await tester.pumpAndSettle();
      expect(
        h.notifier.value.size,
        const CallingCardSize(5.5, 3, CallingCardUnit.inch),
      );

      await tester.enterText(
        find.byKey(const ValueKey('calling-card-height')),
        '20',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calling-card-size-invalid')),
        findsOneWidget,
      );
      expect(
        h.notifier.value.size,
        const CallingCardSize(5.5, 3, CallingCardUnit.inch),
        reason: 'an out-of-range side is never stored',
      );
    });

    testWidgets('changing the unit converts the custom size', (tester) async {
      final h = await _pump(
        tester,
        _section(),
        settings: const CallingCardSettings(
          enabled: true,
          size: CallingCardSize(5.5, 3, CallingCardUnit.inch),
        ),
      );
      expect(find.byKey(const ValueKey('calling-card-width')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calling-card-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Millimetres').last);
      await tester.pumpAndSettle();
      expect(
        h.notifier.value.size,
        const CallingCardSize(139.7, 76.2, CallingCardUnit.millimetre),
      );
    });
  });

  group('layout editor', () {
    late List<Uint8List> rendered;
    Future<Uint8List> rasterizer(Uint8List pdf, double dpi) async {
      rendered.add(pdf);
      return _png;
    }

    setUp(() => rendered = []);

    /// Waits for the preview to have been drawn [count] times.
    Future<void> drawn(WidgetTester tester, int count) async {
      await tester.runAsync(
        () => _settle(tester, () => rendered.length >= count),
      );
      await tester.pump();
    }

    Future<_Harness> pumpEditor(
      WidgetTester tester, {
      CallingCardSettings settings = const CallingCardSettings(enabled: true),
      bool wide = true,
    }) async {
      if (wide) {
        // Two panes: the preview and help have a column of their own.
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      final h = await _pump(
        tester,
        CallingCardLayoutEditorScreen(rasterizer: rasterizer),
        settings: settings,
      );
      await drawn(tester, 1);
      return h;
    }

    TextEditingController controller(WidgetTester tester) => tester
        .widget<TextField>(
          find.byKey(const ValueKey('calling-card-layout-field')),
        )
        .controller!;

    testWidgets('previews the stored layout at the card size', (tester) async {
      // The phone layout: one column.
      await pumpEditor(tester, wide: false);
      expect(rendered, hasLength(1));
      expect(pdfMediaBox(rendered.single), (360, 216));
      expect(
        find.byKey(const ValueKey('calling-card-preview-image')),
        findsOneWidget,
      );
      expect(find.text('A sample dance on a 3 × 5 in card.'), findsOneWidget);
      expect(find.byKey(const ValueKey('calling-card-issues')), findsNothing);
      expect(controller(tester).text, kDefaultCallingCardLayout);
    });

    testWidgets('typing shows problems at once, and saves after a pause', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('calling-card-layout-field')),
        'title\ntitel size=huge',
      );
      await tester.pump();
      expect(
        find.text(
          'Line 2: "titel" isn\'t a block. The blocks are listed under How to '
          'write a layout.',
        ),
        findsOneWidget,
      );
      expect(h.notifier.value.layout, isNull, reason: 'not saved mid-typing');

      await tester.pump(const Duration(milliseconds: 450));
      expect(h.notifier.value.layout, 'title\ntitel size=huge');
      await drawn(tester, 2);
      await tester.runAsync(() async {
        await _settle(tester, () => true);
        expect((await h.stored()).layout, 'title\ntitel size=huge');
      });
    });

    testWidgets('leaving mid-typing still saves', (tester) async {
      final h = await pumpEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('calling-card-layout-field')),
        'title',
      );
      await tester.pumpWidget(const SizedBox());
      expect(h.notifier.value.layout, 'title');
    });

    testWidgets('an example replaces the layout, with Undo', (tester) async {
      final h = await pumpEditor(tester);
      final example = find.byKey(
        const ValueKey('calling-card-example-bigPrint'),
      );
      await tester.ensureVisible(example);
      await tester.pump();
      await tester.tap(example);
      await tester.pump();
      expect(h.notifier.value.layout, kCallingCardLayoutExamples['bigPrint']);
      expect(controller(tester).text, kCallingCardLayoutExamples['bigPrint']);
      // Let the snack bar slide in.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(h.notifier.value.layout, isNull, reason: 'back to the default');
      expect(controller(tester).text, kDefaultCallingCardLayout);
      await drawn(tester, 3);
    });

    testWidgets('Reset asks first, then restores the default', (tester) async {
      final h = await pumpEditor(
        tester,
        settings: const CallingCardSettings(enabled: true, layout: 'title'),
      );
      await tester.tap(find.byKey(const ValueKey('calling-card-reset')));
      await tester.pumpAndSettle();
      expect(h.notifier.value.layout, 'title', reason: 'not before confirming');
      await tester.tap(
        find.byKey(const ValueKey('calling-card-reset-confirm')),
      );
      await tester.pump();
      expect(h.notifier.value.layout, isNull);
      expect(controller(tester).text, kDefaultCallingCardLayout);
      await drawn(tester, 2);
    });

    testWidgets(
      'tapping a name adds a block on its own line, an option in place',
      (tester) async {
        await pumpEditor(
          tester,
          settings: const CallingCardSettings(enabled: true, layout: 'title'),
        );
        controller(tester).selection = const TextSelection.collapsed(offset: 5);
        final chip = find.byKey(const ValueKey('calling-card-insert-figures'));
        await tester.ensureVisible(chip);
        await tester.pump();
        await tester.tap(chip);
        await tester.pump();
        expect(controller(tester).text, 'title\nfigures\n');

        controller(tester).selection = const TextSelection.collapsed(offset: 5);
        final option = find.byKey(const ValueKey('calling-card-insert-bold'));
        await tester.ensureVisible(option);
        await tester.pump();
        await tester.tap(option);
        await tester.pump();
        expect(controller(tester).text, 'title bold\nfigures\n');
        await tester.pump(const Duration(milliseconds: 450));
        await drawn(tester, 2);
      },
    );

    testWidgets('a preview that cannot be drawn says so', (tester) async {
      await _pump(
        tester,
        CallingCardLayoutEditorScreen(
          rasterizer: (_, _) async => throw StateError('no pdfium'),
        ),
        settings: const CallingCardSettings(enabled: true),
      );
      final error = find.byKey(const ValueKey('calling-card-preview-error'));
      await tester.runAsync(
        () => _settle(tester, () => error.evaluate().isNotEmpty),
      );
    });

    testWidgets('a card cut off at half size is called out', (tester) async {
      await pumpEditor(
        tester,
        settings: CallingCardSettings(
          enabled: true,
          layout: 'title\n${'text "${'word ' * 60}"\n' * 30}',
        ),
      );
      expect(
        find.byKey(const ValueKey('calling-card-preview-overflow')),
        findsOneWidget,
      );
    });

    testWidgets('a card that had to shrink says by how much', (tester) async {
      await pumpEditor(
        tester,
        settings: CallingCardSettings(
          enabled: true,
          layout: 'title\nfigures size=16\nnotes size=12',
        ),
      );
      expect(
        find.byKey(const ValueKey('calling-card-preview-shrunk')),
        findsOneWidget,
      );
    });
  });
}

/// Lets real time pass (the preview loads fonts from the asset bundle and
/// writes to the database) until [done], or ten seconds. Call inside
/// `tester.runAsync`.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'timed out waiting');
}
