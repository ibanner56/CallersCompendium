import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/window_service.dart';

void main() {
  test(
    'closes the app before closing the window, only once in flight',
    () async {
      final events = <String>[];
      final coordinator = WindowCloseCoordinator(
        closeApp: () async {
          events.add('close');
          await Future<void>.delayed(Duration.zero);
        },
        closeWindow: () async {
          events.add('close window');
        },
      );

      await Future.wait([coordinator.handle(), coordinator.handle()]);

      expect(events, ['close', 'close window']);
    },
  );

  test(
    'allows the native Windows close path before closing the window',
    () async {
      final events = <String>[];
      final coordinator = WindowCloseCoordinator(
        closeApp: () async => events.add('close app'),
        allowWindowClose: () async => events.add('allow native close'),
        closeWindow: () async => events.add('close window'),
      );

      await coordinator.handle();

      expect(events, ['close app', 'allow native close', 'close window']);
    },
  );

  test('allows a later close attempt after the first completes', () async {
    var closeCount = 0;
    var closeWindowCount = 0;
    final coordinator = WindowCloseCoordinator(
      closeApp: () async {
        closeCount++;
      },
      closeWindow: () async {
        closeWindowCount++;
      },
    );

    await coordinator.handle();
    await coordinator.handle();

    expect(closeCount, 2);
    expect(closeWindowCount, 2);
  });

  test('continues closing after an app-close failure', () async {
    final events = <String>[];
    final coordinator = WindowCloseCoordinator(
      closeApp: () async {
        events.add('close');
        throw StateError('database close failed');
      },
      closeWindow: () async {
        events.add('close window');
      },
    );

    await coordinator.handle();

    expect(events, ['close', 'close window']);
  });

  test('continues closing after allowing native close fails', () async {
    final events = <String>[];
    final coordinator = WindowCloseCoordinator(
      closeApp: () async => events.add('close app'),
      allowWindowClose: () async {
        events.add('allow native close');
        throw StateError('allow close failed');
      },
      closeWindow: () async => events.add('close window'),
    );

    await coordinator.handle();

    expect(events, ['close app', 'allow native close', 'close window']);
  });

  test(
    'reports close-window failures without leaving an unhandled error',
    () async {
      final coordinator = WindowCloseCoordinator(
        closeApp: () async {},
        closeWindow: () async {
          throw StateError('window destroy failed');
        },
      );

      await coordinator.handle();
    },
  );
}
