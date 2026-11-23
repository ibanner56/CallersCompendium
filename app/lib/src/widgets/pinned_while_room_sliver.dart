import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver that keeps its box child pinned to the top of a [CustomScrollView]
/// as Flutter's PinnedHeaderSliver does, while that leaves the list room: once
/// the child, together with whatever is already pinned above it, would cover
/// more than [maxViewportFraction] of the viewport, it scrolls like a
/// [SliverToBoxAdapter] instead.
///
/// Several of these stack: each pins below the ones before it.
///
/// The limit is for large text on a short viewport (a phone in landscape),
/// where a pinned strip of controls could otherwise leave the results a
/// sliver of space, or none.
///
/// Give [child] an opaque background: rows scroll underneath it.
class PinnedWhileRoomSliver extends StatelessWidget {
  const PinnedWhileRoomSliver({
    super.key,
    this.maxViewportFraction = 0.5,
    required this.child,
  }) : assert(maxViewportFraction > 0 && maxViewportFraction <= 1);

  /// The most of the viewport that pinned headers, this one included, may
  /// cover while this one stays pinned.
  final double maxViewportFraction;

  final Widget child;

  @override
  Widget build(BuildContext context) => _PinnedWhileRoomSliver(
    maxViewportFraction: maxViewportFraction,
    // As Flutter's PinnedHeaderSliver does, so the header's nodes stay grouped.
    child: Semantics(container: true, explicitChildNodes: true, child: child),
  );
}

class _PinnedWhileRoomSliver extends SingleChildRenderObjectWidget {
  const _PinnedWhileRoomSliver({
    required this.maxViewportFraction,
    super.child,
  });

  final double maxViewportFraction;

  @override
  RenderPinnedWhileRoomSliver createRenderObject(BuildContext context) =>
      RenderPinnedWhileRoomSliver(maxViewportFraction);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPinnedWhileRoomSliver renderObject,
  ) {
    renderObject.maxViewportFraction = maxViewportFraction;
  }
}

/// The render object behind [PinnedWhileRoomSliver]. Public so tests can read
/// [pinned].
class RenderPinnedWhileRoomSliver extends RenderSliverSingleBoxAdapter {
  RenderPinnedWhileRoomSliver(this._maxViewportFraction);

  double _maxViewportFraction;
  double get maxViewportFraction => _maxViewportFraction;
  set maxViewportFraction(double value) {
    if (value == _maxViewportFraction) return;
    _maxViewportFraction = value;
    markNeedsLayout();
  }

  /// Whether the last layout pinned the child (true) or let it scroll.
  bool get pinned => _pinned;
  bool _pinned = false;

  double get _childExtent {
    if (child == null) return 0;
    return switch (constraints.axis) {
      Axis.vertical => child!.size.height,
      Axis.horizontal => child!.size.width,
    };
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      _pinned ? 0 : -constraints.scrollOffset;

  @override
  void performLayout() {
    final constraints = this.constraints;
    if (child == null) {
      _pinned = false;
      geometry = SliverGeometry.zero;
      return;
    }
    child!.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = _childExtent;
    _pinned =
        _pinnedAbove() + extent <=
        _maxViewportFraction * constraints.viewportMainAxisExtent;
    if (_pinned) {
      // Flutter's PinnedHeaderSliver geometry: drawn below whatever is pinned
      // above (the overlap), and reported as an obstruction so reveal-on-focus
      // scrolls a target clear of it.
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintOrigin: constraints.overlap,
        paintExtent: math.min(
          extent,
          constraints.remainingPaintExtent - constraints.overlap,
        ),
        layoutExtent: clampDouble(
          extent - constraints.scrollOffset,
          0,
          constraints.remainingPaintExtent,
        ),
        maxPaintExtent: extent,
        maxScrollObstructionExtent: extent,
        cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
        hasVisualOverflow: true,
      );
      (child!.parentData! as SliverPhysicalParentData).paintOffset =
          Offset.zero;
    } else {
      // [SliverToBoxAdapter]'s geometry.
      final painted = calculatePaintOffset(constraints, from: 0, to: extent);
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintExtent: painted,
        cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
        maxPaintExtent: extent,
        hitTestExtent: painted,
        hasVisualOverflow:
            extent > constraints.remainingPaintExtent ||
            constraints.scrollOffset > 0,
      );
      setChildParentData(child!, constraints, geometry!);
    }
  }

  /// How much of the viewport the headers before this one cover once pinned:
  /// their full extent, not the constraints' overlap, which grows from
  /// zero as this header slides up under them. Deciding on the overlap made a
  /// header that could not fit stick for a while, then jump behind the others.
  ///
  /// The viewport lays its slivers out in order, so those before this one
  /// already have this pass's geometry. Under any other parent (a sliver
  /// group) the overlap is all there is to go on.
  double _pinnedAbove() {
    final parent = this.parent;
    if (parent is! RenderViewportBase) return constraints.overlap;
    var extent = 0.0;
    for (
      RenderSliver? sliver = parent.childBefore(this);
      sliver != null;
      sliver = parent.childBefore(sliver)
    ) {
      final geometry = sliver.geometry;
      // Slivers before a viewport's centre grow the other way.
      if (geometry == null ||
          sliver.constraints.growthDirection != constraints.growthDirection) {
        break;
      }
      extent += geometry.maxScrollObstructionExtent;
    }
    return extent;
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // As Flutter's PinnedHeaderSliver: a header held in place is not part of
    // what the viewport scrolls, for screen readers either.
    if (_pinned && geometry != null && geometry!.layoutExtent < _childExtent) {
      config.addTagForChildren(RenderViewport.excludeFromScrolling);
    }
  }
}
