import 'package:compendium_app/src/data/online_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnlineSource tag capability', () {
    test('ContraDB takes the Advanced query but no tag, so it hides tags', () {
      expect(OnlineSource.contraDb.supportsAdvanced, isTrue);
      expect(OnlineSource.contraDb.supportsAdvancedTags, isFalse);
      expect(OnlineSource.contraDb.hidesAdvancedTags, isTrue);
    });

    test("The Caller's Box has no Advanced panel, so it hides nothing", () {
      expect(OnlineSource.callersBox.supportsAdvanced, isFalse);
      expect(OnlineSource.callersBox.hidesAdvancedTags, isFalse);
    });
  });
}
