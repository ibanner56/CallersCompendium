import 'package:compendium_app/src/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows icon, title and body, with no action row by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const EmptyState(
          icon: Icon(Icons.inbox),
          title: 'Nothing here',
          body: 'Add something.',
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add something.'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('renders every action and omits a missing body', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        EmptyState(
          icon: const Icon(Icons.inbox),
          title: 'Nothing here',
          actions: [
            FilledButton(onPressed: () => taps++, child: const Text('Add')),
            OutlinedButton(onPressed: () {}, child: const Text('Import')),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    expect(taps, 1);
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets('scrolls instead of overflowing in a short pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 120));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        EmptyState(
          icon: const Icon(Icons.inbox, size: 64),
          title: 'Nothing here',
          body: 'Add something.',
          actions: [FilledButton(onPressed: () {}, child: const Text('Add'))],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
