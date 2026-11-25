// The search field's saved-search dropdown on its own (#2325): what decides
// when it shows, and that choosing a row never writes to the field.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/widgets/saved_search_field.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final _day = DateTime.utc(2026, 11, 23);

class _Host extends StatefulWidget {
  const _Host({super.key, required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool enabled = true;
  int revision = 0;
  int submitted = 0;
  final loaded = <String>[];

  void set({bool? enabled, bool bump = false}) => setState(() {
    if (enabled != null) this.enabled = enabled;
    if (bump) revision++;
  });

  @override
  Widget build(BuildContext context) => SavedSearchField(
    controller: widget.controller,
    focusNode: widget.focusNode,
    enabled: enabled,
    revision: revision,
    onLoad: (s) => loaded.add(s.id),
    onSubmitted: () => submitted++,
    fieldBuilder: (context, onSubmitted) => TextField(
      key: const ValueKey('field'),
      controller: widget.controller,
      focusNode: widget.focusNode,
      onSubmitted: (_) => onSubmitted(),
    ),
  );
}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester,
  CompendiumRepositories repos,
  TextEditingController controller,
  FocusNode focusNode,
) async {
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _Host(key: key, controller: controller, focusNode: focusNode),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<SavedSearch> _seed(CompendiumRepositories repos, String name) =>
    repos.savedSearches.create(
      name: name,
      spec: SavedSearchSpec.fromPanelState(
        CollectionPanelState(text: name),
        today: _day,
      ).value!,
    );

final _dropdown = find.byKey(const ValueKey('saved-search-dropdown'));

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('a list that arrives while the field already has focus opens '
      'the dropdown without a keystroke', (tester) async {
    final repos = openTestRepositories();
    final host = await _pump(tester, repos, controller, focusNode);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    expect(_dropdown, findsNothing, reason: 'nothing saved yet');

    final saved = await _seed(repos, 'Becket');
    host.currentState!.set(bump: true);
    await tester.pumpAndSettle();

    expect(_dropdown, findsOneWidget);
    expect(find.byKey(ValueKey('saved-search-row-${saved.id}')), findsOne);
  });

  testWidgets('turning Online search off while the field has focus opens the '
      'dropdown again', (tester) async {
    final repos = openTestRepositories();
    await _seed(repos, 'Becket');
    final host = await _pump(tester, repos, controller, focusNode);
    host.currentState!.set(enabled: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    expect(_dropdown, findsNothing);

    host.currentState!.set(enabled: true);
    await tester.pumpAndSettle();

    expect(_dropdown, findsOneWidget);
  });

  testWidgets('choosing Search for leaves the text, cursor and composition '
      'as they were', (tester) async {
    final repos = openTestRepositories();
    await _seed(repos, 'Becket');
    final host = await _pump(tester, repos, controller, focusNode);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    // Mid-word, with an IME composition under way (as in Japanese input).
    const value = TextEditingValue(
      text: 'beck',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 4),
    );
    controller.value = value;
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('saved-search-search-for')));
    await tester.pump();

    expect(controller.value, value);
    expect(host.currentState!.submitted, 1);
  });
}
