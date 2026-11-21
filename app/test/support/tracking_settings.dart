import 'package:compendium_app/src/data/calling_history_tracking_scope.dart';
import 'package:flutter/widgets.dart';

/// Mounts the four tracking-toggle scopes with their shipped defaults, the way
/// `main.dart` does, for a settings harness that reads or flips them.
class TrackingScopes extends StatefulWidget {
  const TrackingScopes({super.key, required this.child});

  final Widget child;

  @override
  State<TrackingScopes> createState() => _TrackingScopesState();
}

class _TrackingScopesState extends State<TrackingScopes> {
  final _eventDate = ValueNotifier<bool>(true);
  final _performed = ValueNotifier<bool?>(null);
  final _undated = ValueNotifier<bool>(false);
  final _unperformed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _eventDate.dispose();
    _performed.dispose();
    _undated.dispose();
    _unperformed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RecencyRequireEventDateScope(
    notifier: _eventDate,
    child: RecencyRequirePerformedScope(
      notifier: _performed,
      child: HistoryOrderIgnoreUndatedScope(
        notifier: _undated,
        child: HistoryOrderIgnoreUnperformedScope(
          notifier: _unperformed,
          child: widget.child,
        ),
      ),
    ),
  );
}
