import 'package:flutter/widgets.dart';

/// A pending "add this tag to the Collection's filter" request (issue #414,
/// FIND-14).
///
/// [seq] is a monotonically increasing token so that tapping the *same* tag
/// twice still counts as a new request — listeners compare the seq they last
/// applied rather than the tag id, so a repeat tap re-triggers navigation and
/// re-adds the tag (e.g. after the user cleared it).
@immutable
class CollectionTagFilterRequest {
  const CollectionTagFilterRequest({required this.tagId, required this.seq});

  /// The id of the tag to filter the Collection list to.
  final String tagId;

  /// Unique, increasing token distinguishing this request from earlier ones.
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is CollectionTagFilterRequest &&
      other.tagId == tagId &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(tagId, seq);
}

/// Coordinates a "tap a tag → add it to the Collection's filter" action
/// (issue #414, FIND-14) across the app without coupling the tag chips (dance
/// detail, list rows) to the Collection screen or the top-level shell.
///
/// A tag chip calls [filterByTag]; the running [AppShell] switches to the
/// Collection destination (and pops any pushed detail route), and the live
/// `DanceListScreen` adds the tag to its Tags facet, keeping the rest of the
/// search — both by listening to this controller.
class CollectionFilterController extends ChangeNotifier {
  CollectionTagFilterRequest? _pending;
  int _seq = 0;

  /// The most recent filter request, or `null` if none has been made yet.
  CollectionTagFilterRequest? get pending => _pending;

  /// Requests that [tagId] be added to the Collection list's filter. Notifies
  /// listeners so the shell navigates and the list adds the tag.
  void filterByTag(String tagId) {
    _pending = CollectionTagFilterRequest(tagId: tagId, seq: ++_seq);
    notifyListeners();
  }
}

/// Exposes a [CollectionFilterController] to the widget tree.
///
/// Provided in `main.dart` **above the root [Navigator]** (in
/// `MaterialApp.builder`), so it is reachable both from the Collection screen
/// kept alive in the shell's `IndexedStack` and from a `DanceDetailScreen`
/// pushed as a route on the root navigator.
///
/// Optional by design: [maybeOf] returns `null` in focused widget tests that
/// don't mount it (and in the online-preview detail view, where filtering the
/// local collection is meaningless), so callers must null-check.
class CollectionFilterScope
    extends InheritedNotifier<CollectionFilterController> {
  const CollectionFilterScope({
    super.key,
    required CollectionFilterController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, or `null` when no scope is present.
  static CollectionFilterController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectionFilterScope>()
      ?.notifier;
}
