import 'package:flutter/widgets.dart';

/// Observes the lifetime of a recognized long press without entering the
/// gesture arena, so an unrelated pointer cannot end the active preview.
class PreviewHoldListener extends StatefulWidget {
  const PreviewHoldListener({
    super.key,
    required this.childBuilder,
    this.onPreviewStarted,
    this.onPreviewEnded,
  });

  final Widget Function(VoidCallback? onLongPress) childBuilder;
  final VoidCallback? onPreviewStarted;
  final VoidCallback? onPreviewEnded;

  @override
  State<PreviewHoldListener> createState() => _PreviewHoldListenerState();
}

class _PreviewHoldListenerState extends State<PreviewHoldListener> {
  int? _candidatePointer;
  int? _previewPointer;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.onPreviewStarted == null) return;
    _candidatePointer ??= event.pointer;
  }

  void _handleLongPress() {
    final candidatePointer = _candidatePointer;
    if (candidatePointer == null) return;
    _previewPointer = candidatePointer;
    widget.onPreviewStarted!();
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_candidatePointer == event.pointer) {
      _candidatePointer = null;
    }
    if (_previewPointer != event.pointer) return;
    _previewPointer = null;
    widget.onPreviewEnded?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: widget.childBuilder(
        widget.onPreviewStarted == null ? null : _handleLongPress,
      ),
    );
  }
}
