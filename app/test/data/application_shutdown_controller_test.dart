import 'dart:async';

import 'package:compendium_app/src/data/application_shutdown_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shares an in-flight close request', () async {
    final completer = Completer<void>();
    var closeCount = 0;
    final controller = ApplicationShutdownController(() {
      closeCount++;
      return completer.future;
    });

    final first = controller.close();
    final second = controller.close();

    expect(identical(first, second), isTrue);
    expect(closeCount, 1);

    completer.complete();
    await first;
  });

  test('uses the replacement database close action after reset', () async {
    var firstCloseCount = 0;
    var replacementCloseCount = 0;
    final controller = ApplicationShutdownController(() async {
      firstCloseCount++;
    });

    await controller.close();
    controller.replaceCloseApp(() async {
      replacementCloseCount++;
    });
    await controller.close();

    expect(firstCloseCount, 1);
    expect(replacementCloseCount, 1);
  });
}
