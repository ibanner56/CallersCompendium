import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/window_service.dart';

void main() {
  test('closes the app before destroying the window, only once', () async {
    final events = <String>[];
    final coordinator = WindowCloseCoordinator(
      closeApp: () async {
        events.add('close');
        await Future<void>.delayed(Duration.zero);
      },
      destroyWindow: () async {
        events.add('destroy');
      },
    );

    await Future.wait([coordinator.handle(), coordinator.handle()]);

    expect(events, ['close', 'destroy']);
  });

  test('reports close failures without leaving an unhandled error', () async {
    final events = <String>[];
    final coordinator = WindowCloseCoordinator(
      closeApp: () async {
        events.add('close');
        throw StateError('database close failed');
      },
      destroyWindow: () async {
        events.add('destroy');
      },
    );

    await coordinator.handle();

    expect(events, ['close', 'destroy']);
  });

  test('reports destroy failures without leaving an unhandled error', () async {
    final coordinator = WindowCloseCoordinator(
      closeApp: () async {},
      destroyWindow: () async {
        throw StateError('window destroy failed');
      },
    );

    await coordinator.handle();
  });
}
