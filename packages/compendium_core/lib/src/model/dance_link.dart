import 'package:meta/meta.dart';

import 'enums.dart';

/// A link attached to a dance: a source citation, a video, a related dance
/// in the collection, or anything else.
///
/// Invariant: exactly the right target for its [kind] — [relatedDance] links
/// carry [targetDanceId]; all others carry [url]. At least one must be set.
/// Only related-dance links may be [transitive].
@immutable
class DanceLink {
  DanceLink({
    required this.id,
    required this.kind,
    this.url,
    this.targetDanceId,
    this.label,
    this.transitive = false,
  }) {
    if (kind == LinkKind.relatedDance) {
      if (targetDanceId == null) {
        throw ArgumentError(
          'relatedDance links require targetDanceId',
          'targetDanceId',
        );
      }
      if (url != null) {
        throw ArgumentError('relatedDance links must not carry a url', 'url');
      }
    } else if (transitive) {
      throw ArgumentError(
        '${kind.name} links must not be transitive',
        'transitive',
      );
    } else {
      if (url == null || url!.trim().isEmpty) {
        throw ArgumentError('${kind.name} links require a url', 'url');
      }
      if (targetDanceId != null) {
        throw ArgumentError(
          '${kind.name} links must not carry a targetDanceId',
          'targetDanceId',
        );
      }
    }
  }

  final String id;
  final LinkKind kind;
  final String? url;
  final String? targetDanceId;
  final String? label;
  final bool transitive;

  @override
  bool operator ==(Object other) =>
      other is DanceLink &&
      other.id == id &&
      other.kind == kind &&
      other.url == url &&
      other.targetDanceId == targetDanceId &&
      other.label == label &&
      other.transitive == transitive;

  @override
  int get hashCode =>
      Object.hash(id, kind, url, targetDanceId, label, transitive);
}
