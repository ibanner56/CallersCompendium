import 'package:compendium_app/src/data/window_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowFrame JSON', () {
    test('round-trips size, position, and maximized', () {
      const frame = WindowFrame(
        width: 1200,
        height: 800,
        x: 120,
        y: 60,
        maximized: true,
      );
      final decoded = WindowFrame.fromJson(frame.toJson());
      expect(decoded, frame);
    });

    test('omits null position from JSON', () {
      const frame = WindowFrame(width: 1024, height: 768);
      final json = frame.toJson();
      expect(json.containsKey('x'), isFalse);
      expect(json.containsKey('y'), isFalse);
      expect(json['maximized'], isFalse);
    });

    test('decodes with missing position (centers → null x/y)', () {
      final frame = WindowFrame.fromJson({'width': 900, 'height': 700});
      expect(frame, isNotNull);
      expect(frame!.width, 900);
      expect(frame.height, 700);
      expect(frame.hasPosition, isFalse);
      expect(frame.maximized, isFalse);
    });

    test('falls back to defaults for missing/invalid size', () {
      final frame = WindowFrame.fromJson({'width': 'nope', 'height': -5});
      expect(frame, isNotNull);
      expect(frame!.width, WindowFrame.defaultWidth);
      expect(frame.height, WindowFrame.defaultHeight);
    });

    test('treats missing maximized as false and reads truthy flag', () {
      expect(
        WindowFrame.fromJson({'width': 800, 'height': 600})!.maximized,
        isFalse,
      );
      expect(
        WindowFrame.fromJson({
          'width': 800,
          'height': 600,
          'maximized': true,
        })!.maximized,
        isTrue,
      );
    });

    test('returns null for non-map input', () {
      expect(WindowFrame.fromJson(null), isNull);
      expect(WindowFrame.fromJson('x'), isNull);
      expect(WindowFrame.fromJson(42), isNull);
    });
  });

  group('WindowFrame.clampToBounds', () {
    test('leaves a well-fitting frame unchanged', () {
      const frame = WindowFrame(width: 1000, height: 700, x: 50, y: 40);
      final clamped = frame.clampToBounds(
        visibleWidth: 1920,
        visibleHeight: 1080,
      );
      expect(clamped, frame);
    });

    test('shrinks an oversized frame to the display size', () {
      const frame = WindowFrame(width: 4000, height: 3000, x: 0, y: 0);
      final clamped = frame.clampToBounds(
        visibleWidth: 1280,
        visibleHeight: 800,
      );
      expect(clamped.width, 1280);
      expect(clamped.height, 800);
    });

    test('enforces the minimum size', () {
      const frame = WindowFrame(width: 100, height: 100, x: 10, y: 10);
      final clamped = frame.clampToBounds(
        visibleWidth: 1920,
        visibleHeight: 1080,
      );
      expect(clamped.width, WindowFrame.minWidth);
      expect(clamped.height, WindowFrame.minHeight);
    });

    test('repositions a frame that is off the right/bottom edges', () {
      const frame = WindowFrame(width: 800, height: 600, x: 1800, y: 1000);
      final clamped = frame.clampToBounds(
        visibleWidth: 1920,
        visibleHeight: 1080,
      );
      expect(clamped.x, 1920 - 800);
      expect(clamped.y, 1080 - 600);
    });

    test('repositions a frame that is off the top/left edges', () {
      const frame = WindowFrame(width: 800, height: 600, x: -300, y: -200);
      final clamped = frame.clampToBounds(
        visibleWidth: 1920,
        visibleHeight: 1080,
      );
      expect(clamped.x, 0);
      expect(clamped.y, 0);
    });

    test('honors a non-zero visible origin (secondary monitor)', () {
      const frame = WindowFrame(width: 800, height: 600, x: 100, y: 50);
      final clamped = frame.clampToBounds(
        visibleWidth: 1440,
        visibleHeight: 900,
        visibleX: 1920,
        visibleY: 0,
      );
      // x=100 is left of this display's origin (1920) → pulled to the origin.
      expect(clamped.x, 1920);
      expect(clamped.y, 50);
    });

    test('pins an oversized frame to the visible origin', () {
      const frame = WindowFrame(width: 5000, height: 5000, x: 200, y: 200);
      final clamped = frame.clampToBounds(
        visibleWidth: 1000,
        visibleHeight: 800,
        visibleX: 30,
        visibleY: 20,
      );
      expect(clamped.width, 1000);
      expect(clamped.height, 800);
      expect(clamped.x, 30);
      expect(clamped.y, 20);
    });

    test('preserves the maximized flag and leaves null position null', () {
      const frame = WindowFrame(width: 3000, height: 700, maximized: true);
      final clamped = frame.clampToBounds(
        visibleWidth: 1280,
        visibleHeight: 800,
      );
      expect(clamped.maximized, isTrue);
      expect(clamped.hasPosition, isFalse);
      expect(clamped.width, 1280);
    });
  });
}
