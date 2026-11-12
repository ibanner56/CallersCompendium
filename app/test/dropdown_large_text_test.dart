// Large-text overflow guards for the form dropdowns that #2162 left alone.
//
// A `DropdownButtonFormField` without `isExpanded` sizes itself to its widest
// item, so a long label (a user's custom-field name, a choice, a difficulty
// level, a column title) overflows its row at phone width and large text. Each
// case pumps the real widget at 360 dp with the system text scale at 2.0 (and
// 1.5), using the bundled fonts, filled with realistic long values, and asserts
// that no RenderFlex overflow was reported.
//
// The widgets are pumped directly rather than reached through a lazy list, so
// the site is certain to be built (the #2162 sweep only builds what is on
// screen).
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/custom_fields_screen.dart';
import 'package:compendium_app/src/screens/dance_editor/custom_field_editor.dart';
import 'package:compendium_app/src/screens/dance_editor/editor_fields.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/settings/matrix_column_editor.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/batch_custom_field_dialog.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/real_fonts.dart';
import 'support/screen_size.dart';
import 'support/test_repositories.dart';

const _phone = Size(360, 780);

/// Realistic worst cases: what a user types into a field name or option, which
/// no translation or fixed list bounds.
const _longFieldLabel = 'Preferred band for the evening contra at the hall';
const _longChoice =
    'Requires an experienced caller and a live band with a fiddle';

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required double scale,
  Locale? locale,
  CompendiumRepositories? repos,
}) async {
  await loadBundledFonts();
  await setScreenSize(tester, _phone);
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      theme: AppTheme.light,
      builder: (context, child) {
        Widget app = ActiveDialectScope(
          notifier: notifier,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        );
        if (repos != null) {
          app = RepositoriesScope(repositories: repos, child: app);
        }
        return app;
      },
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// A RenderFlex overflow is reported as a framework exception.
void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// For a dropdown whose items are user-typed: the closed field ellipsizes the
/// selected [full] text, and the open menu shows all of it (it wraps), so the
/// value can always be read somewhere.
Future<void> _expectEllipsizedClosedReadableOpen(
  WidgetTester tester,
  Finder field,
  String full,
) async {
  bool exceeds(Finder f) =>
      tester.renderObject<RenderParagraph>(f).didExceedMaxLines;
  final closed = find.descendant(of: field, matching: find.text(full));
  expect(closed, findsOneWidget);
  expect(exceeds(closed), isTrue, reason: 'closed field should ellipsize');
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  final inMenu = find.text(full).last;
  expect(exceeds(inMenu), isFalse, reason: 'open menu should show it in full');
  _expectNoOverflow(tester);
}

/// Every `Text` inside the open menu's items must lay out in full and be
/// allowed to wrap (no ellipsis, no line cap).
void _expectMenuItemsUnclipped<T>(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(DropdownMenuItem<T>),
    matching: find.byType(Text),
  );
  expect(texts, findsWidgets);
  for (final element in texts.evaluate()) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidget(element.widget),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    // A label that happens to fit must still be free to wrap: a menu item that
    // ellipsizes would silently truncate a longer translation or larger text.
    final text = element.widget as Text;
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(text.maxLines, isNull);
  }
}

Widget _scaffold(Widget body) => Scaffold(
  body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
);

void main() {
  for (final scale in [1.5, 2.0]) {
    group('at ${scale}x', () {
      group('CustomFieldEditor choice dropdown', () {
        for (final withAdd in [false, true]) {
          testWidgets('long label and options'
              '${withAdd ? ' beside the add-option button' : ''}', (
            tester,
          ) async {
            await _pump(
              tester,
              _scaffold(
                CustomFieldEditor(
                  def: CustomFieldDef(
                    id: 'f1',
                    key: 'band',
                    label: _longFieldLabel,
                    type: CustomFieldType.choice,
                    choices: const [_longChoice, 'Short'],
                  ),
                  dialect: Dialect.larksRobins,
                  textController: null,
                  currentValue: _longChoice,
                  onTextChanged: () {},
                  onValueChanged: (_) {},
                  onAddOption: withAdd
                      ? (_) async => throw UnimplementedError()
                      : null,
                ),
              ),
              scale: scale,
            );
            _expectNoOverflow(tester);
            await _expectEllipsizedClosedReadableOpen(
              tester,
              find.byKey(const ValueKey('custom-f1-choice')),
              _longChoice,
            );
          });
        }
      });

      testWidgets('LevelDropdown with a long difficulty level name', (
        tester,
      ) async {
        final long = DifficultyLevel(
          id: 'long',
          label: 'Challenging but only for confident dancers',
          position: 0,
        );
        await _pump(
          tester,
          _scaffold(
            LevelDropdown(
              value: long,
              levels: [long, DifficultyLevel.beginner],
              onChanged: (_) {},
            ),
          ),
          scale: scale,
        );
        _expectNoOverflow(tester);
        await _expectEllipsizedClosedReadableOpen(
          tester,
          find.byKey(const ValueKey('level-field')),
          long.label,
        );
      });

      for (final locale in testSupportedLocales) {
        testWidgets('PartialDateField Month and Day in $locale', (
          tester,
        ) async {
          await _pump(
            tester,
            _scaffold(
              PartialDateField(
                fieldKey: 'composed',
                label: 'Composed',
                helperText: 'Year, then optionally month and day',
                // September has a long name in several locales.
                value: PartialDate(1998, 9, 28),
                onChanged: (_) {},
              ),
            ),
            scale: scale,
            locale: locale,
          );
          _expectNoOverflow(tester);
        });
      }

      group('batch custom field dialog', () {
        Future<void> open(
          WidgetTester tester,
          List<CustomFieldDef> defs,
        ) async {
          await _pump(
            tester,
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () => showBatchCustomFieldDialog(
                    context,
                    defs: defs,
                    repos: openTestRepositories(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
            scale: scale,
          );
          await tester.tap(find.byKey(const ValueKey('open')));
          await tester.pumpAndSettle();
        }

        testWidgets('long field name selected in the key dropdown', (
          tester,
        ) async {
          await open(tester, [
            CustomFieldDef(
              id: 'f1',
              key: 'band',
              label: _longFieldLabel,
              type: CustomFieldType.text,
            ),
          ]);
          _expectNoOverflow(tester);
          await _expectEllipsizedClosedReadableOpen(
            tester,
            find.byKey(const ValueKey('batch-custom-field-key')),
            _longFieldLabel,
          );
        });

        testWidgets('long choice label in the value dropdown', (tester) async {
          await open(tester, [
            CustomFieldDef(
              id: 'f1',
              key: 'band',
              label: _longFieldLabel,
              type: CustomFieldType.choice,
              choices: const [_longChoice, 'Short'],
            ),
          ]);
          // Select the long option so the closed dropdown renders it.
          await tester.tap(
            find.byKey(const ValueKey('batch-custom-field-value-f1-2')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(_longChoice).last);
          await tester.pumpAndSettle();
          _expectNoOverflow(tester);
          await _expectEllipsizedClosedReadableOpen(
            tester,
            find.byKey(const ValueKey('batch-custom-field-value-f1-2')),
            _longChoice,
          );
        });
      });

      for (final locale
          in scale < 2 ? const <Locale>[] : testSupportedLocales) {
        testWidgets('custom field form type dropdown in $locale', (
          tester,
        ) async {
          final repos = openTestRepositories();
          await _pump(
            tester,
            const CustomFieldsScreen(),
            scale: scale,
            locale: locale,
            repos: repos,
          );
          await tester.tap(find.byKey(const ValueKey('add-field')));
          await tester.pumpAndSettle();
          _expectNoOverflow(tester);
          expect(find.byKey(const ValueKey('cf-type')), findsOneWidget);
        });
      }

      for (final locale
          in scale < 2 ? const <Locale>[] : testSupportedLocales) {
        testWidgets('program status dropdown in $locale', (tester) async {
          final repos = openTestRepositories();
          await _pump(
            tester,
            const ProgramEditorScreen(),
            scale: scale,
            locale: locale,
            repos: repos,
          );
          final tile = find.byKey(const ValueKey('program-more-details-tile'));
          await tester.ensureVisible(tile);
          tester.widget<ExpansionTile>(tile).controller!.expand();
          await tester.pumpAndSettle();
          final status = find.byKey(const ValueKey('program-status'));
          await tester.scrollUntilVisible(
            status,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(status, findsOneWidget);
          _expectNoOverflow(tester);
          // Open the menu: every status label must show in full there.
          await tester.ensureVisible(status);
          await tester.pumpAndSettle();
          await tester.tap(status);
          await tester.pumpAndSettle();
          _expectMenuItemsUnclipped<ProgramStatus>(tester);
          _expectNoOverflow(tester);
        });
      }

      group('matrix column dialogs', () {
        // The longest real move name in the shipped taxonomy: the realistic
        // worst case, since these items come from the taxonomy.
        final longest = contraTaxonomy.moves.values.reduce(
          (a, b) => a.displayName.length >= b.displayName.length ? a : b,
        );
        final taxonomy = Taxonomy(
          version: contraTaxonomy.version,
          form: contraTaxonomy.form,
          moves: [longest],
        );

        Future<void> openDialog(WidgetTester tester, String addKey) async {
          await _pump(
            tester,
            Scaffold(
              body: MatrixColumnEditor(
                config: MatrixColumnConfig.empty,
                dialect: Dialect.larksRobins,
                taxonomy: taxonomy,
                onConfigChanged: (_) {},
              ),
            ),
            scale: scale,
          );
          await tester.ensureVisible(find.byKey(ValueKey(addKey)));
          await tester.tap(find.byKey(ValueKey(addKey)));
          await tester.pumpAndSettle();
        }

        testWidgets('parameterized column move dropdown', (tester) async {
          await openDialog(tester, 'matrix-column-add-parameterized');
          _expectNoOverflow(tester);
          await _expectEllipsizedClosedReadableOpen(
            tester,
            find.byKey(const ValueKey('matrix-parameterized-move')),
            longest.displayName,
          );
        });

        testWidgets('compound column step move dropdown', (tester) async {
          await openDialog(tester, 'matrix-column-add-compound');
          // Add a step so a step dropdown is built.
          final add = find.byKey(const ValueKey('matrix-compound-add-step'));
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          _expectNoOverflow(tester);
          await _expectEllipsizedClosedReadableOpen(
            tester,
            find.byKey(const ValueKey('matrix-compound-step-move-0')),
            longest.displayName,
          );
        });
      });
    });
  }
}
