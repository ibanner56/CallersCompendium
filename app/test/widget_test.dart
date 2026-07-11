import 'package:compendium_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots and shows its title', (tester) async {
    await tester.pumpWidget(const CompendiumApp());
    expect(find.text("Caller's Compendium"), findsOneWidget);
  });
}
