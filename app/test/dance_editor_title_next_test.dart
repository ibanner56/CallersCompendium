import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// The Title field's keyboard action: on a new dance it hands the caller on
/// to the figures, so a phone's keyboard stays up, rather than focusing the
/// setup panel's header, which takes no typing and closed the keyboard.
Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? danceId,
  Size size = const Size(390, 2400),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: DanceEditorScreen(danceId: danceId),
    ),
  );
  await tester.pumpAndSettle();
}

final _title = find.byKey(const ValueKey('title-field'));

TextInputAction? _titleAction(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _title, matching: find.byType(EditableText)),
    )
    .textInputAction;

/// Whether the text field under [finder] holds the focus.
bool _focused(WidgetTester tester, Finder finder) => tester
    .widget<EditableText>(
      find.descendant(of: finder, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

void main() {
  testWidgets('on a new dance, Next opens the first placeholder figure and '
      'keeps the keyboard up', (tester) async {
    await _pump(tester, openTestRepositories());
    expect(_focused(tester, _title), isTrue);
    expect(_titleAction(tester), TextInputAction.next);

    await tester.enterText(_title, 'Hole in the Wall');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    final move = find.byKey(const ValueKey('figure-0-move-input'));
    expect(move, findsOneWidget);
    expect(_focused(tester, move), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('with Free-text entry on, Next opens the composer', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kFreeTextEntryKey, true);
    await _pump(tester, repos);
    expect(_titleAction(tester), TextInputAction.next);

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final composer = find.byKey(const ValueKey('figure-free-text-field'));
    expect(composer, findsOneWidget);
    expect(_focused(tester, composer), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('on an existing dance, the key is Done and closes the keyboard', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Old',
        figures: defaultNewDanceFigureTemplate(),
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos, danceId: 'd1');
    await tester.tap(_title);
    await tester.pumpAndSettle();
    expect(_titleAction(tester), TextInputAction.done);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_focused(tester, _title), isFalse);
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsNothing);
    // Focus moves on to what follows the Title, as Flutter's default would,
    // so a keyboard user keeps their place rather than losing focus.
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byElementPredicate((element) => element == focused),
        matching: find.byKey(const ValueKey('setup-tile')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('on a new dance whose figures are all set, the key is Done', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures([
        Figure(move: 'swing', params: const {'beats': 8}),
      ]),
    );
    await _pump(tester, repos);
    expect(_titleAction(tester), TextInputAction.done);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_focused(tester, _title), isFalse);
  });

  // The form is a lazy list: on a short screen, or with the setup panel open
  // above them, the figures are not built when Next is pressed.
  for (final (name, size) in [
    ('a tablet with the keyboard up, panel open', const Size(900, 450)),
    ('a short phone', const Size(390, 500)),
  ]) {
    testWidgets('on $name, Next still reaches the figures', (tester) async {
      await _pump(tester, openTestRepositories(), size: size);
      final move = find.byKey(const ValueKey('figure-0-move-input'));
      expect(move, findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(move, findsOneWidget);
      expect(_focused(tester, move), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  }

  testWidgets('Next reaches a figure that is already open', (tester) async {
    await _pump(tester, openTestRepositories());
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final move = find.byKey(const ValueKey('figure-0-move-input'));
    expect(_focused(tester, move), isTrue);

    await tester.tap(_title);
    await tester.pumpAndSettle();
    expect(_focused(tester, _title), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(_focused(tester, move), isTrue);
  });
}
