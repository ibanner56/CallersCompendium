import 'package:compendium_app/src/widgets/program_matrix_table.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13);

  Dance dance(String id, String title, List<Figure> figures) => Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );

  Figure move(String id) => Figure(move: id);
  Figure swing([String? who]) => Figure(move: 'swing', params: {'who': ?who});
  Figure hey([String? length]) =>
      Figure(move: 'hey', params: {'length': ?length});

  Future<void> pump(
    WidgetTester tester, {
    required List<Dance> dances,
    int omittedFreeTextCount = 0,
    Set<String> altDanceIds = const {},
    Dialect? dialect,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgramMatrixTable(
            matrix: buildProgramMatrix(dances),
            taxonomy: contraTaxonomy,
            dialect: dialect ?? Dialect.canonical,
            omittedFreeTextCount: omittedFreeTextCount,
            altDanceIds: altDanceIds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders move column headers and dance row headers', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'Butterfly', [swing(), move('balance')]),
        dance('d2', 'Broken Sixpence', [swing()]),
      ],
    );

    // Row headers (dance titles).
    expect(find.text('Butterfly'), findsOneWidget);
    expect(find.text('Broken Sixpence'), findsOneWidget);
    // Swing is split by role: a partner-swing column (shared) plus the
    // always-present neighbor-swing baseline.
    expect(find.text('partner swing'), findsOneWidget);
    expect(find.text('neighbor swing'), findsOneWidget);
    expect(find.text('balance'), findsOneWidget);
  });

  testWidgets('renders split swing and hey headers present in the program', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing('role1s'), hey('full')]),
      ],
      dialect: Dialect.larksRobins,
    );

    // Baseline swing columns always render...
    expect(find.text('partner swing'), findsOneWidget);
    expect(find.text('neighbor swing'), findsOneWidget);
    // ...the present role split renders (dialect-aware role term)...
    expect(find.text('lark swing'), findsOneWidget);
    // ...and the present hey length renders (full only — no half baseline).
    expect(find.text('full hey'), findsOneWidget);
    expect(find.text('half hey'), findsNothing);
  });

  testWidgets('presence marks use an icon + semantics, not colour alone', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('balance'), swing()]),
      ],
    );

    // balance is the first figure (star); the partner swing is present but not
    // first (check). Both are shapes, so presence never relies on colour alone.
    expect(find.byIcon(Icons.check), findsWidgets);
    expect(find.byIcon(Icons.star), findsWidgets);

    // Cell semantics announce dance × move × state.
    expect(find.bySemanticsLabel('A, partner swing: present'), findsOneWidget);
    expect(find.bySemanticsLabel('A, balance: first figure'), findsOneWidget);
  });

  testWidgets('first-figure highlight lands on the correct split column', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing('neighbors')]),
      ],
    );

    // The legend spells out the meaning of each shape in text.
    expect(find.text('First figure'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    // A opens with a neighbor swing → the neighbor split column is the first
    // figure; the partner baseline is not present for this dance.
    expect(
      find.bySemanticsLabel('A, neighbor swing: first figure'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('A, partner swing: not present'),
      findsOneWidget,
    );
  });

  testWidgets('header cells are flagged as semantic headers', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
      ],
    );

    expect(find.bySemanticsLabel('Move: partner swing'), findsOneWidget);
    expect(find.bySemanticsLabel('Dance: A'), findsOneWidget);
  });

  testWidgets('absent cell announces "not present"', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
        dance('d2', 'B', [move('balance')]),
      ],
    );
    // A has no balance; B has no swing (so the baseline partner-swing column is
    // absent for B).
    expect(find.bySemanticsLabel('A, balance: not present'), findsOneWidget);
    expect(
      find.bySemanticsLabel('B, partner swing: not present'),
      findsOneWidget,
    );
  });

  testWidgets('empty matrix (no dances) shows the auto-fill empty state', (
    tester,
  ) async {
    await pump(tester, dances: const []);
    expect(find.text('No structured figures yet'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('empty matrix still notes omitted free-text slots', (
    tester,
  ) async {
    await pump(tester, dances: const [], omittedFreeTextCount: 3);
    expect(find.text('No structured figures yet'), findsOneWidget);
    expect(find.textContaining('3 free-text slots'), findsOneWidget);
  });

  testWidgets('omitted free-text slots are noted in a caption', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
      ],
      omittedFreeTextCount: 2,
    );
    expect(find.textContaining('2 free-text slots'), findsOneWidget);
  });

  testWidgets('alt dances are badged in the row header', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
        dance('d2', 'Alt Dance', [move('balance')]),
      ],
      altDanceIds: {'d2'},
    );
    expect(find.text('ALT'), findsOneWidget);
    expect(find.bySemanticsLabel('Alternate dance: Alt Dance'), findsOneWidget);
  });

  testWidgets('column labels honour the active dialect', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
      ],
      dialect: Dialect(name: 'Test', moves: const {'swing': 'twirl'}),
    );
    expect(find.text('partner twirl'), findsOneWidget);
    expect(find.text('neighbor twirl'), findsOneWidget);
    expect(find.text('partner swing'), findsNothing);
  });
}
