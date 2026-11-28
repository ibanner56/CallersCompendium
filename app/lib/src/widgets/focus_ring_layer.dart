import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_shapes.dart';
import '../theme/app_theme_extension.dart';

/// Draws the keyboard-focus ring ([AppThemeExtension.focusRing],
/// [AppThemeExtension.focusRingWidth]) around whatever has keyboard focus, in
/// the focused widget's own theme.
///
/// Material's own focus cue is the theme's `focusColor`, a translucent fill
/// that changes the focused pixels by roughly 1.2:1 — too faint to see across
/// a room or to meet WCAG 2.4.13 (Focus Appearance). Buttons, chips and inputs
/// can take a state-aware border from their themes, but [ListTile],
/// [NavigationRail], [NavigationBar], [Checkbox], [Switch] and radio buttons
/// cannot.
/// One layer above the app therefore draws the same ring for every focusable
/// widget, *outside* its bounds: the ring's pixels were the canvas before, so
/// its contrast is the ring colour against the surface tiers, which
/// `palette_contrast_test.dart` holds to 3:1 for every scheme.
///
/// The colour and width come from the [Theme] nearest the focused widget, not
/// from the layer's: a subtree can wear a theme of its own over a canvas of
/// its own. Perform's stage mode (`PerformStageTheme`) dresses its page,
/// dialogs and sheets in the dark High contrast theme whatever the app theme
/// is, so a control there gets that theme's ochre ring; the app theme's
/// primary, tuned for its own canvas, can fall under 3:1 on the stage
/// (`focus_ring_layer_test.dart`).
///
/// The ring shows only in [FocusHighlightMode.traditional] (keyboard
/// traversal), as Material's own focus highlight does. It is not drawn for:
///
/// * a text field, whose own `focusedBorder` already draws the ring;
/// * a focus scope, or a node covering most of the layer — the page-level
///   `Focus(autofocus: true)` wrappers that exist only to receive keyboard
///   shortcuts, where a ring round the whole page says nothing;
/// * a node scrolled out of its scrollable's viewport. The ring is clipped to
///   every enclosing viewport, widened only by the ring's own width, so a row
///   half under an app bar shows at most that sliver of ring over the bar.
class FocusRingLayer extends StatefulWidget {
  const FocusRingLayer({super.key, required this.child});

  final Widget child;

  /// Gap between the focused widget's edge and the ring's inner edge.
  static const double gap = 2;

  /// A node whose bounds cover more than this share of the layer is a
  /// page-level shortcut receiver, not a control, and gets no ring.
  static const double maxAreaShare = 0.6;

  @override
  State<FocusRingLayer> createState() => FocusRingLayerState();
}

/// State of [FocusRingLayer]; public only so tests can read [ringRect].
class FocusRingLayerState extends State<FocusRingLayer> {
  final GlobalKey _layerKey = GlobalKey();

  /// The ring's target rectangle (the focused widget's bounds) in the layer's
  /// coordinates, or `null` when no ring is drawn.
  @visibleForTesting
  Rect? get ringRect => _rect;
  Rect? _rect;
  Rect? _clip;

  /// The focused widget's own ring: its theme's colour and width.
  ({Color color, double width})? _style;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_schedule);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    // Scrolling, resizing and route transitions move the focused widget
    // without a focus change, so re-measure after every frame. A persistent
    // callback cannot be removed, so a disposed state ignores it. setState
    // runs only when the rectangle moved, so this never keeps frames coming
    // on its own; when it does run, it runs from a post-frame callback,
    // where (unlike during the persistent callbacks) it schedules the frame
    // that repaints the ring.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_schedule);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) => _schedule();

  void _schedule() {
    if (!mounted) return;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _measure())
      ..scheduleFrame();
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final target = _target();
    final rect = target?.$1;
    final clip = target?.$2;
    final style = target?.$3;
    if (rect == _rect && clip == _clip && style == _style) return;
    setState(() {
      _rect = rect;
      _clip = clip;
      _style = style;
    });
  }

  (Rect, Rect, ({Color color, double width})?)? _target() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) return null;
    final context = node.context;
    if (context == null || !context.mounted) return null;
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return null;
    }
    final layer = _layerKey.currentContext?.findRenderObject();
    final target = context.findRenderObject();
    if (layer is! RenderBox || !layer.attached || !layer.hasSize) return null;
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(layer),
      Offset.zero & target.size,
    );
    // A row a lazy list keeps alive off-screen has no paint transform, which
    // comes back as NaN.
    if (!rect.isFinite) return null;
    final area = layer.size.width * layer.size.height;
    if (area <= 0 ||
        rect.width * rect.height > area * FocusRingLayer.maxAreaShare) {
      return null;
    }

    // Clip to every enclosing viewport, so the ring on a row scrolled under
    // an app bar or past a sheet's edge is cut off with the row.
    var clip = Offset.zero & layer.size;
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final box = scrollable.context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        clip = clip.intersect(
          MatrixUtils.transformRect(
            box.getTransformTo(layer),
            Offset.zero & box.size,
          ),
        );
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    if (clip.isEmpty || !clip.overlaps(rect)) return null;
    // The nearest Theme's data, read without making the focused widget
    // depend on it. `null` (no theme of its own above it, or one without the
    // app's extension) falls back to the layer's theme in [build].
    final ext = context
        .findAncestorWidgetOfExactType<Theme>()
        ?.data
        .extension<AppThemeExtension>();
    return (
      rect,
      clip,
      ext == null ? null : (color: ext.focusRing, width: ext.focusRingWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = AppThemeExtension.of(context);
    final style = _style ?? (color: ext.focusRing, width: ext.focusRingWidth);
    final rect = _rect;
    final clip = _clip;
    return Stack(
      key: _layerKey,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (rect != null && clip != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: FocusRingPainter(
                  rect: rect,
                  clip: clip,
                  color: style.color,
                  width: style.width,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints the ring for [FocusRingLayer]; public so tests can read what it
/// draws.
@visibleForTesting
class FocusRingPainter extends CustomPainter {
  FocusRingPainter({
    required this.rect,
    required this.clip,
    required this.color,
    required this.width,
  });

  final Rect rect;
  final Rect clip;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    // A stroke straddles its path, so push the path out by half the width:
    // the whole ring then sits outside the widget, [FocusRingLayer.gap] away.
    final outset = FocusRingLayer.gap + width / 2;
    final ring = RRect.fromRectAndRadius(
      rect.inflate(outset),
      const Radius.circular(AppShapes.radiusSmall),
    );
    canvas
      ..save()
      ..clipRect(clip.inflate(outset + width / 2))
      ..drawRRect(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.rect != rect ||
      old.clip != clip ||
      old.color != color ||
      old.width != width;
}
