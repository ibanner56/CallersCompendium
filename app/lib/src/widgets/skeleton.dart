import 'package:flutter/material.dart';

import '../data/reduce_motion_scope.dart';
import '../theme/app_spacing.dart';

/// Content-shaped loading placeholders ("skeletons").
///
/// Instead of a bare centred [CircularProgressIndicator] on a blank pane, list
/// and detail views render neutral blocks shaped like the real rows/fields so
/// the layout is stable and the wait feels shorter (`docs/design/ux.md` loading
/// states). A subtle shimmer sweeps across the blocks; it is disabled when the
/// user has turned on **Reduce motion** ([ReduceMotionScope]), leaving static
/// neutral blocks.
///
/// Every composite wraps its blocks in a single [Semantics] node labelled
/// "Loading…" (and excludes the decorative blocks from the tree) so assistive
/// technology announces the loading state once, clearly.

/// Default accessibility label announced while a skeleton is visible.
const String kSkeletonLoadingLabel = 'Loading\u2026';

/// A single neutral placeholder block. Width defaults to filling the available
/// horizontal space (useful inside a stretched [Column]); pass an explicit
/// [width] or wrap in an [Expanded]/[SizedBox] to control it.
class SkeletonBone extends StatelessWidget {
  const SkeletonBone({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.borderRadius,
  });

  /// A round bone (e.g. a placeholder for a leading [CircleAvatar]).
  const SkeletonBone.circle(double size, {super.key})
    : width = size,
      height = size,
      borderRadius = const BorderRadius.all(Radius.circular(999));

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Derived from onSurface so it adapts across light / dark /
        // high-contrast themes. Purely decorative — the surrounding [Semantics]
        // conveys the loading state — so no text-contrast requirement applies.
        color: scheme.onSurface.withValues(alpha: 0.11),
        borderRadius: borderRadius ?? BorderRadius.circular(6),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

/// Wraps a tree of [SkeletonBone]s and animates a shimmer highlight across
/// them. Honours **Reduce motion**: when it is on, the child renders statically
/// with no animation or [ShaderMask].
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncMotion(bool reduceMotion) {
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ReduceMotionScope.of(context);
    _syncMotion(reduceMotion);
    if (reduceMotion) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.11);
    final highlight = scheme.onSurface.withValues(alpha: 0.04);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final slide = (_controller.value * 2 - 1) * bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideTransform(slide),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// A list of content-shaped placeholder rows, shaped like a Collection /
/// Programs result row (leading avatar, title line, a couple of meta chips).
class SkeletonListView extends StatelessWidget {
  const SkeletonListView({
    super.key,
    this.rowCount = 6,
    this.label = kSkeletonLoadingLabel,
  });

  final int rowCount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Shimmer(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rowCount,
            itemBuilder: (context, _) => const _SkeletonListRow(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonListRow extends StatelessWidget {
  const _SkeletonListRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBone.circle(40),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBone(width: 180, height: 16),
                SizedBox(height: 10),
                Row(
                  children: [
                    SkeletonBone(width: 96, height: 12),
                    SizedBox(width: AppSpacing.xs),
                    SkeletonBone(width: 56, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A detail-pane placeholder shaped like a dance/record detail: a header card
/// (title, subtitle, two meta rows, a paragraph) followed by a section heading
/// and a few field rows.
class SkeletonDetailView extends StatelessWidget {
  const SkeletonDetailView({super.key, this.label = kSkeletonLoadingLabel});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Shimmer(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              Card(
                color: scheme.surfaceContainer,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBone(width: 220, height: 28),
                      SizedBox(height: 10),
                      SkeletonBone(width: 140, height: 16),
                      SizedBox(height: AppSpacing.md),
                      SkeletonBone(width: 180, height: 14),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonBone(width: 160, height: 14),
                      SizedBox(height: AppSpacing.md),
                      SkeletonBone(height: 14),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonBone(height: 14),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonBone(width: 240, height: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SkeletonBone(width: 100, height: 18),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < 4; i++) ...const [
                SkeletonBone(height: 14),
                SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact skeleton for the command palette's loading state: a few short
/// icon+text rows shaped like search results.
class SkeletonResultRows extends StatelessWidget {
  const SkeletonResultRows({
    super.key,
    this.rowCount = 4,
    this.label = kSkeletonLoadingLabel,
  });

  final int rowCount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Shimmer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rowCount; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      SkeletonBone(width: 24, height: 24),
                      SizedBox(width: AppSpacing.md),
                      Expanded(child: SkeletonBone(height: 14)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
