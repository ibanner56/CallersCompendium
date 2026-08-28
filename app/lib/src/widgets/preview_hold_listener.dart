import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Recognizes a stationary hold without entering the gesture arena.
///
/// This keeps scroll and drag gestures independent while preserving the pointer
/// that began the hold through its end or cancellation.
class PreviewHoldListener extends StatefulWidget {
  const PreviewHoldListener({
    super.key,
    required this.child,
    this.onPreviewStarted,
    this.onPreviewEnded,
  });

  final Widget child;
  final VoidCallback? onPreviewStarted;
  final VoidCallback? onPreviewEnded;

  @override
  State<PreviewHoldListener> createState() => _PreviewHoldListenerState();
}

class _PreviewHoldListenerState extends State<PreviewHoldListener> {
  final _pendingHolds = <int, _PendingHold>{};
  final _previewPointers = <int>{};

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.onPreviewStarted == null) return;
    final hold = _PendingHold(event.position);
    _pendingHolds[event.pointer] = hold;
    hold.timer = Timer(kLongPressTimeout, () {
      if (!mounted || !identical(_pendingHolds[event.pointer], hold)) return;
      _pendingHolds.remove(event.pointer);
      final onPreviewStarted = widget.onPreviewStarted;
      if (onPreviewStarted == null) return;
      if (_previewPointers.isEmpty) {
        _previewPointers.add(event.pointer);
        onPreviewStarted();
      } else {
        _previewPointers.add(event.pointer);
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final hold = _pendingHolds[event.pointer];
    if (hold == null) return;
    if ((event.position - hold.startPosition).distanceSquared >
        kTouchSlop * kTouchSlop) {
      _cancelPendingHold(event.pointer);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    _cancelPendingHold(event.pointer);
    if (!_previewPointers.remove(event.pointer) ||
        _previewPointers.isNotEmpty) {
      return;
    }
    widget.onPreviewEnded?.call();
  }

  void _cancelPendingHold(int pointer) {
    _pendingHolds.remove(pointer)?.timer?.cancel();
  }

  @override
  void dispose() {
    for (final hold in _pendingHolds.values) {
      hold.timer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      // The passive timer owns the preview lifecycle. This recognizer only
      // rejects a child tap after a hold has been recognized.
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPress: widget.onPreviewStarted == null ? null : () {},
        child: widget.child,
      ),
    );
  }
}

class _PendingHold {
  _PendingHold(this.startPosition);

  final Offset startPosition;
  Timer? timer;
}
