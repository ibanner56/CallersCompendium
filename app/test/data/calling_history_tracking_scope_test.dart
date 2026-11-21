import 'package:compendium_app/src/data/calling_history_tracking_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ValueNotifier<bool> requirePerformed;
  late ValueNotifier<bool?> recencyPerformed;
  late CallingHistoryTracking? seen;
  var builds = 0;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    RequirePerformedForHistoryScope(
      notifier: requirePerformed,
      child: RecencyRequireEventDateScope(
        notifier: ValueNotifier(true),
        child: RecencyRequirePerformedScope(
          notifier: recencyPerformed,
          child: HistoryOrderIgnoreUndatedScope(
            notifier: ValueNotifier(false),
            child: HistoryOrderIgnoreUnperformedScope(
              notifier: ValueNotifier(false),
              child: Builder(
                builder: (context) {
                  builds++;
                  seen = callingHistoryTrackingOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  setUp(() {
    requirePerformed = ValueNotifier(false);
    recencyPerformed = ValueNotifier(null);
    seen = null;
    builds = 0;
  });

  testWidgets('with no scopes the shipped defaults apply', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = callingHistoryTrackingOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(seen, CallingHistoryTracking.defaults);
  });

  testWidgets('recency-requires-performed follows the global setting until '
      'set, and a stored value wins', (tester) async {
    await pump(tester);
    expect(seen!.recencyRequirePerformed, isFalse);
    requirePerformed.value = true;
    await tester.pump();
    expect(seen!.recencyRequirePerformed, isTrue);
    recencyPerformed.value = false;
    await tester.pump();
    expect(seen!.recencyRequirePerformed, isFalse);
    requirePerformed.value = false;
    recencyPerformed.value = true;
    await tester.pump();
    expect(seen!.recencyRequirePerformed, isTrue);
    expect(builds, greaterThan(1));
  });
}
