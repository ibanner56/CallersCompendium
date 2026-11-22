import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  const beats = ParamBeats(
    param: 'fraction',
    byValue: {'half': 4},
    rules: [
      ParamBeatsRule({'size': 'eight', 'fraction': 'full'}, 16),
      ParamBeatsRule({'size': 'eight', 'fraction': 'half'}, 8),
    ],
  );

  test('a rule matches only when every value it names matches', () {
    expect(beats.derive({'size': 'eight', 'fraction': 'full'}), 16);
    expect(beats.derive({'size': 'four', 'fraction': 'full'}), isNull);
  });

  test('a rule wins over the single-parameter table', () {
    expect(beats.derive({'size': 'eight', 'fraction': 'half'}), 8);
    expect(beats.derive({'size': 'four', 'fraction': 'half'}), 4);
  });

  test('a move with no rules reads its table as before', () {
    const plain = ParamBeats(param: 'prefix', byValue: {'balance': 16});
    expect(plain.rules, isEmpty);
    expect(plain.derive({'prefix': 'balance'}), 16);
    expect(plain.derive({'prefix': 'none'}), isNull);
  });
}
