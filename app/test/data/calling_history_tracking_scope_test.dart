import 'package:compendium_app/src/data/calling_history_tracking_scope.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ValueNotifier<bool> requirePerformed;
  late ValueNotifier<bool?> recencyPerformed;
  late CallingHistoryTrackingSettings settings;

  setUp(() {
    requirePerformed = ValueNotifier(false);
    recencyPerformed = ValueNotifier(null);
    settings = CallingHistoryTrackingSettings(
      requirePerformedForHistory: requirePerformed,
      recencyRequireEventDate: ValueNotifier(true),
      recencyRequirePerformed: recencyPerformed,
      orderIgnoreUndated: ValueNotifier(false),
      orderIgnoreUnperformed: ValueNotifier(false),
    );
  });

  test('defaults resolve to the shipped defaults', () {
    expect(settings.resolve(), CallingHistoryTracking.defaults);
  });

  test('recency-requires-performed follows the global setting until set', () {
    requirePerformed.value = true;
    expect(settings.resolve().recencyRequirePerformed, isTrue);
    // A stored value wins, in either direction.
    recencyPerformed.value = false;
    expect(settings.resolve().recencyRequirePerformed, isFalse);
    requirePerformed.value = false;
    recencyPerformed.value = true;
    expect(settings.resolve().recencyRequirePerformed, isTrue);
  });

  test('the listenable fires when the global setting changes', () {
    var fired = 0;
    settings.listenable.addListener(() => fired++);
    requirePerformed.value = true;
    expect(fired, 1);
  });
}
