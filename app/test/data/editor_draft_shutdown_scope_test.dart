import 'dart:async';

import 'package:compendium_app/src/data/application_shutdown_controller.dart';
import 'package:compendium_app/src/data/editor_draft_shutdown_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prepares every registration before awaiting the first operation',
    () async {
      final controller = EditorDraftShutdownController();
      final firstGate = Completer<void>();
      final prepared = <int>[];
      final executed = <int>[];

      controller.register(() {
        prepared.add(1);
        return () async {
          executed.add(1);
          await firstGate.future;
        };
      });
      controller.register(() {
        prepared.add(2);
        return () async {
          executed.add(2);
        };
      });

      final flush = controller.flushAll();
      expect(prepared, [1, 2]);
      expect(executed, [1]);

      firstGate.complete();
      await flush;
      expect(executed, [1, 2]);
    },
  );

  test('continues after one prepared operation fails', () async {
    final controller = EditorDraftShutdownController();
    var secondRan = false;

    controller.register(
      () => () async {
        throw StateError('first failure');
      },
    );
    controller.register(
      () => () async {
        secondRan = true;
      },
    );

    await controller.flushAll();
    expect(secondRan, isTrue);
  });

  test(
    'the close wrapper flushes before initial and replacement closes',
    () async {
      final drafts = EditorDraftShutdownController();
      final events = <String>[];
      drafts.register(
        () => () async {
          events.add('flush');
        },
      );
      final shutdown = ApplicationShutdownController(
        () =>
            flushEditorDraftsThenClose(drafts, () async => events.add('first')),
      );

      await shutdown.close();
      expect(events, ['flush', 'first']);

      shutdown.replaceCloseApp(
        () => flushEditorDraftsThenClose(
          drafts,
          () async => events.add('second'),
        ),
      );
      await shutdown.close();
      expect(events, ['flush', 'first', 'flush', 'second']);
    },
  );
}
