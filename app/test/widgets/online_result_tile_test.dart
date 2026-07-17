import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OnlineSearchResultRow _result({
  OnlineSource source = OnlineSource.callersBox,
  String id = '10600',
  String name = 'Money Musk',
  String author = 'Traditional',
  String formation = 'Triple Minor - Proper',
}) => OnlineSearchResultRow(
  source: source,
  id: id,
  name: name,
  author: author,
  formation: formation,
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  ),
);

void main() {
  testWidgets('renders title, author, formation and the online attribution', (
    tester,
  ) async {
    await _pump(tester, OnlineResultTile(result: _result()));

    expect(find.text('Money Musk'), findsOneWidget);
    expect(find.text('Traditional • Triple Minor - Proper'), findsOneWidget);
    expect(find.text("From The Caller's Box (online)"), findsOneWidget);
  });

  testWidgets('renders the ContraDB attribution for a ContraDB row', (
    tester,
  ) async {
    await _pump(
      tester,
      OnlineResultTile(result: _result(source: OnlineSource.contraDb)),
    );

    expect(find.text('Money Musk'), findsOneWidget);
    expect(find.text('From ContraDB (online)'), findsOneWidget);
  });

  testWidgets('omits the middle line when author and formation are empty', (
    tester,
  ) async {
    await _pump(
      tester,
      OnlineResultTile(
        result: _result(author: '', formation: ''),
      ),
    );

    expect(find.text('Money Musk'), findsOneWidget);
    // Only the attribution line, no empty " • " separator row.
    expect(find.textContaining('•'), findsNothing);
    expect(find.text("From The Caller's Box (online)"), findsOneWidget);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      OnlineResultTile(result: _result(), onTap: () => taps++),
    );

    await tester.tap(find.byType(OnlineResultTile));
    expect(taps, 1);
  });
}
