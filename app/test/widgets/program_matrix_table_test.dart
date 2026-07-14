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

  Future<void> pump(
    WidgetTester tester, {
    required List<Dance> dances,
    int omittedFreeTextCount = 0,
    Set<String> altDanceIds = const {},
    Dialect? dialect,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
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
        dance('d1', 'Butterfly', [move('swing'), move('balance')]),
        dance('d2', 'Broken Sixpence', [move('swing')]),
      ],
    );

    // Row headers (dance titles).
    expect(find.text('Butterfly'), findsOneWidget);
    expect(find.text('Broken Sixpence'), findsOneWidget);
    // Column headers (move labels): swing appears once (shared column).
    expect(find.text('swing'), findsOneWidget);
    expect(find.text('balance'), findsOneWidget);
  });

  testWidgets('presence marks use an icon + semantics, not colour alone', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('balance'), move('swing')]),
      ],
    );

    // balance is the first figure (star); swing is present but not first
    // (check). Both are shapes, so presence never relies on colour alone.
    expect(find.byIcon(Icons.check), findsWidgets);
    expect(find.byIcon(Icons.star), findsWidgets);

    // Cell semantics announce dance × move × state.
    expect(find.bySemanticsLabel('A, swing: present'), findsOneWidget);
    expect(find.bySemanticsLabel('A, balance: first figure'), findsOneWidget);
  });

  testWidgets('first-figure indicator has icon + text (not colour only)', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('swing')]),
      ],
    );

    // The legend spells out the meaning of each shape in text.
    expect(find.text('First figure'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    // The first figure of the only dance is a star.
    expect(find.byIcon(Icons.star), findsWidgets);
    expect(find.bySemanticsLabel('A, swing: first figure'), findsOneWidget);
  });

  testWidgets('header cells are flagged as semantic headers', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('swing')]),
      ],
    );

    expect(find.bySemanticsLabel('Move: swing'), findsOneWidget);
    expect(find.bySemanticsLabel('Dance: A'), findsOneWidget);
  });

  testWidgets('absent cell announces "not present"', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('swing')]),
        dance('d2', 'B', [move('balance')]),
      ],
    );
    // A has no balance; B has no swing.
    expect(find.bySemanticsLabel('A, balance: not present'), findsOneWidget);
    expect(find.bySemanticsLabel('B, swing: not present'), findsOneWidget);
  });

  testWidgets('empty matrix shows the auto-fill empty state', (tester) async {
    await pump(tester, dances: [dance('d1', 'Stub', const [])]);
    expect(find.text('No structured figures yet'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('omitted free-text slots are noted in a caption', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('swing')]),
      ],
      omittedFreeTextCount: 2,
    );
    expect(find.textContaining('2 free-text slots'), findsOneWidget);
  });

  testWidgets('alt dances are badged in the row header', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [move('swing')]),
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
        dance('d1', 'A', [move('swing')]),
      ],
      dialect: Dialect(name: 'Test', moves: const {'swing': 'twirl'}),
    );
    expect(find.text('twirl'), findsOneWidget);
    expect(find.text('swing'), findsNothing);
  });
}
