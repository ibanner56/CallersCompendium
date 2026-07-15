import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('danceDetailRenderingFromStored', () {
    test('round-trips every rendering via .name', () {
      for (final rendering in DanceDetailRendering.values) {
        expect(danceDetailRenderingFromStored(rendering.name), rendering);
      }
    });

    test(
      'falls back to activeDialect for null, non-strings, unknown names',
      () {
        expect(
          danceDetailRenderingFromStored(null),
          DanceDetailRendering.activeDialect,
        );
        expect(
          danceDetailRenderingFromStored(7),
          DanceDetailRendering.activeDialect,
        );
        expect(
          danceDetailRenderingFromStored('nope'),
          DanceDetailRendering.activeDialect,
        );
      },
    );
  });
}
