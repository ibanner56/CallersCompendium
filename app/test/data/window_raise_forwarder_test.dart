import 'package:compendium_app/src/data/window_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/full_app_harness.dart';

/// A [WindowService] that records [raise] calls instead of driving the plugin.
class _RecordingWindowService extends NoopWindowService {
  _RecordingWindowService(super.settings);

  int raised = 0;

  @override
  Future<void> raise() async => raised++;
}

void main() {
  late _RecordingWindowService first;
  late _RecordingWindowService replacement;

  setUp(() {
    final appData = openTestAppData();
    addTearDown(appData.close);
    first = _RecordingWindowService(appData.repositories.settings);
    replacement = _RecordingWindowService(appData.repositories.settings);
  });

  test('a raise before any service exists is ignored', () {
    WindowRaiseForwarder().raise();
  });

  test('raise reaches the registered service', () {
    final forwarder = WindowRaiseForwarder();
    expect(forwarder.register(first), same(first));

    forwarder.raise();

    expect(first.raised, 1);
  });

  test(
    'after Retry or reset replaces the service, raise reaches the replacement '
    'and not the disposed original',
    () {
      final forwarder = WindowRaiseForwarder()..register(first);

      forwarder.register(replacement);
      forwarder.raise();

      expect(replacement.raised, 1);
      expect(first.raised, 0);
    },
  );
}
