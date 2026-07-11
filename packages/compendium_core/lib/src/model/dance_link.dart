import 'package:meta/meta.dart';

import 'enums.dart';

/// A link attached to a dance: a source citation, a video, a related dance
/// in the collection, or anything else.
///
/// Invariant: exactly the right target for its [kind] — [relatedDance] links
/// carry [targetDanceId]; all others carry [url]. At least one must be set.
@immutable
class DanceLink {
  DanceLink({
    required this.id,
    required this.kind,
    this.url,
    this.targetDanceId,
    this.label,
  }) {
    if (kind == LinkKind.relatedDance) {
      if (targetDanceId == null) {
        throw ArgumentError(
          'relatedDance links require targetDanceId',
          'targetDanceId',
        );
      }
    } else if (url == null || url!.trim().isEmpty) {
      throw ArgumentError('${kind.name} links require a url', 'url');
    }
  }

  final String id;
  final LinkKind kind;
  final String? url;
  final String? targetDanceId;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is DanceLink &&
      other.id == id &&
      other.kind == kind &&
      other.url == url &&
      other.targetDanceId == targetDanceId &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, kind, url, targetDanceId, label);
}
