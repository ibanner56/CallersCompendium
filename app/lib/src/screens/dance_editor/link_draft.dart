import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import '../../editor/editor_snapshot.dart';

/// Mutable editing state for a single [DanceLink] (all four [LinkKind]s).
///
/// URL-kind links (source/video/other) use [urlController]; relatedDance links
/// use [targetDanceId]. The [labelController] is shared by all kinds.
class LinkDraft {
  LinkDraft({
    required this.id,
    required LinkKind kind,
    required this.urlController,
    required this.labelController,
    this.targetDanceId,
  }) : _kind = kind; // ignore: prefer_initializing_formals

  factory LinkDraft.empty() => LinkDraft(
    id: uuidV4(),
    kind: LinkKind.source,
    urlController: TextEditingController(),
    labelController: TextEditingController(),
  );

  /// A blank relatedDance draft (no target selected yet) for the dedicated
  /// Related-dances subsection.
  factory LinkDraft.relatedDance() => LinkDraft(
    id: uuidV4(),
    kind: LinkKind.relatedDance,
    urlController: TextEditingController(),
    labelController: TextEditingController(),
  );

  factory LinkDraft.fromLink(DanceLink link) => LinkDraft(
    id: link.id,
    kind: link.kind,
    urlController: TextEditingController(text: link.url ?? ''),
    labelController: TextEditingController(text: link.label ?? ''),
    targetDanceId: link.targetDanceId,
  );

  /// Reconstructs a draft from an [EditorSnapshot]'s [LinkSnapshot], used
  /// when applying an undo/redo snapshot or restoring an autosave draft.
  factory LinkDraft.fromSnapshot(LinkSnapshot s) => LinkDraft(
    id: s.id,
    kind: s.kind,
    urlController: TextEditingController(text: s.url),
    labelController: TextEditingController(text: s.label),
    targetDanceId: s.targetDanceId,
  );

  final String id;
  LinkKind _kind;

  LinkKind get kind => _kind;

  set kind(LinkKind value) {
    if (_kind == value) return;
    _kind = value;
    // Clear incompatible state when switching between URL and relatedDance.
    if (value == LinkKind.relatedDance) {
      urlController.clear();
    } else {
      targetDanceId = null;
    }
  }

  final TextEditingController urlController;
  final TextEditingController labelController;

  /// Set when [kind] is [LinkKind.relatedDance]; `null` otherwise.
  String? targetDanceId;

  /// Builds a [DanceLink], or `null` when the required target is absent.
  ///
  /// For relatedDance: returns `null` if no dance has been selected yet.
  /// For URL kinds: returns `null` if the URL field is blank.
  DanceLink? toLink() {
    final label = labelController.text.trim();
    if (kind == LinkKind.relatedDance) {
      final target = targetDanceId;
      if (target == null || target.isEmpty) return null;
      return DanceLink(
        id: id,
        kind: kind,
        targetDanceId: target,
        label: label.isEmpty ? null : label,
      );
    } else {
      final url = urlController.text.trim();
      if (url.isEmpty) return null;
      return DanceLink(
        id: id,
        kind: kind,
        url: url,
        label: label.isEmpty ? null : label,
      );
    }
  }

  void dispose() {
    urlController.dispose();
    labelController.dispose();
  }
}
