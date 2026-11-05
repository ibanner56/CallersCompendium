import 'package:compendium_app/src/data/calling_history_tracking_scope.dart';
import 'package:flutter/foundation.dart';

/// Tracking-toggle notifiers wired the way `main.dart` wires them: the second
/// follows [requirePerformed] until it is set.
CallingHistoryTrackingSettings testTrackingSettings(
  ValueListenable<bool> requirePerformed,
) => CallingHistoryTrackingSettings(
  requirePerformedForHistory: requirePerformed,
  recencyRequireEventDate: ValueNotifier<bool>(true),
  recencyRequirePerformed: ValueNotifier<bool?>(null),
  orderIgnoreUndated: ValueNotifier<bool>(false),
  orderIgnoreUnperformed: ValueNotifier<bool>(false),
);
