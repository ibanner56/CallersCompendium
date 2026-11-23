import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../export/dance_code.dart';
import '../export/share_file.dart';
import '../screens/perform_wakelock.dart';
import '../theme/app_spacing.dart';
import 'brand_mark.dart';

/// How much of the code's width the brand mark covers (#2334). The issue asks
/// for about 15 to 20%. Only a level H code (30% of it can be lost) is drawn
/// with the mark, and `dance_code_render_test.dart` decodes a rendered one to
/// show it still scans.
const double kDanceCodeMarkFraction = 0.18;

/// The white square the mark sits in, as a multiple of the mark's own size.
const double _clearZoneFactor = 1.18;

/// A QR code needs a quiet zone of at least this many modules on each side.
const int _quietZoneModules = 4;

/// A code is dark modules on a light card, in every theme: scanners expect it,
/// and a dark theme would invert it. These are deliberately not theme colours.
const Color _codeLight = Colors.white;
const Color _codeDark = Colors.black;

/// A dance shown as a full-screen QR code to hold up for another caller
/// (#2334): the code, the brand mark in its middle when the plan allows one,
/// and the dance's title underneath. The screen is kept awake while it shows.
///
/// The code is always dark modules on a light card, whatever the app theme:
/// scanners expect that, and a dark theme would invert it.
class DanceCodeScreen extends StatefulWidget {
  const DanceCodeScreen({
    super.key,
    required this.plan,
    required this.title,
    @visibleForTesting this.markFraction = kDanceCodeMarkFraction,
  });

  final DanceCodeShown plan;
  final String title;

  /// Fraction of the code's width the mark covers. Tests turn this up to
  /// find where a code stops scanning.
  final double markFraction;

  @override
  State<DanceCodeScreen> createState() => _DanceCodeScreenState();
}

class _DanceCodeScreenState extends State<DanceCodeScreen>
    with WidgetsBindingObserver, PerformWakelockMixin {
  late final Path _modules = _modulePath(widget.plan);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = widget.plan;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.danceCodeScreenTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final available = constraints.biggest.shortestSide;
                      final span = plan.moduleCount + 2 * _quietZoneModules;
                      // Whole device pixels per module: a scanner reads a
                      // blurred edge worse than a crisp one. (Where is the
                      // card? `_CodePainter` snaps that to a whole pixel.) If
                      // not even one pixel per module fits, the window is too
                      // small to scan from anyway: fit the code to it.
                      final wholePixels = (available * dpr / span).floor();
                      final module = wholePixels >= 1
                          ? wholePixels / dpr
                          : available / span;
                      final side = module * span;
                      return Semantics(
                        label: l10n.danceCodeSemanticLabel(widget.title),
                        image: true,
                        child: ExcludeSemantics(
                          child: SizedBox.square(
                            dimension: side,
                            child: _CodeCard(
                              key: const ValueKey('dance-code'),
                              plan: plan,
                              modules: _modules,
                              module: module,
                              markFraction: plan.withMark
                                  ? widget.markFraction
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Text(
                widget.title,
                key: const ValueKey('dance-code-title'),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    super.key,
    required this.plan,
    required this.modules,
    required this.module,
    required this.markFraction,
  });

  final DanceCodeShown plan;
  final Path modules;
  final double module;
  final double? markFraction;

  @override
  Widget build(BuildContext context) {
    final codeSide = module * plan.moduleCount;
    final mark = markFraction == null ? null : codeSide * markFraction!;
    return ColoredBox(
      color: _codeLight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CodePainter(modules, module, _quietZoneModules),
            ),
          ),
          if (mark != null) ...[
            Container(
              width: mark * _clearZoneFactor,
              height: mark * _clearZoneFactor,
              decoration: BoxDecoration(
                color: _codeLight,
                borderRadius: BorderRadius.circular(mark * 0.12),
              ),
            ),
            BrandMark(size: mark, showTile: true),
          ],
        ],
      ),
    );
  }
}

/// All the dark modules as one path in module units: a run of dark modules in
/// a row is one rectangle.
Path _modulePath(DanceCodeShown plan) {
  final path = Path();
  final n = plan.moduleCount;
  for (var row = 0; row < n; row++) {
    var column = 0;
    while (column < n) {
      if (!plan.isDark(row, column)) {
        column++;
        continue;
      }
      final start = column;
      while (column < n && plan.isDark(row, column)) {
        column++;
      }
      path.addRect(
        Rect.fromLTWH(
          start.toDouble(),
          row.toDouble(),
          (column - start).toDouble(),
          1,
        ),
      );
    }
  }
  return path;
}

/// How far to move a canvas, in its own units, so its origin lands on a whole
/// device pixel. [transform] is the canvas's transform, taken to be a scale
/// and a translation (as Flutter's is for ordinary layout).
@visibleForTesting
Offset pixelSnapShift(Float64List transform) {
  final scaleX = transform[0];
  final scaleY = transform[5];
  if (scaleX == 0 || scaleY == 0) return Offset.zero;
  return Offset(
    (transform[12].roundToDouble() - transform[12]) / scaleX,
    (transform[13].roundToDouble() - transform[13]) / scaleY,
  );
}

class _CodePainter extends CustomPainter {
  _CodePainter(this.modules, this.module, this.quietZone);

  final Path modules;
  final double module;
  final int quietZone;

  @override
  void paint(Canvas canvas, Size size) {
    // Wherever layout put the card, start on a whole device pixel: the module
    // size is whole pixels, so then every edge is too.
    final shift = pixelSnapShift(canvas.getTransform());
    canvas
      ..translate(shift.dx, shift.dy)
      ..translate(quietZone * module, quietZone * module)
      ..scale(module);
    canvas.drawPath(
      modules,
      Paint()
        ..color = _codeDark
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_CodePainter old) =>
      old.modules != modules || old.module != module;
}

/// Shown instead of a code when the dance does not fit one at any level: says
/// so, and offers the dance file in the same place.
class DanceCodeTooLongScreen extends StatelessWidget {
  const DanceCodeTooLongScreen({
    super.key,
    required this.title,
    required this.onShareFile,
  });

  final String title;

  /// Starts the dance-file share or save, given where on screen the button is
  /// (the share sheet of an iPad or a Mac anchors to it).
  final void Function(Rect? origin) onShareFile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unsupported = isBundleShareUnsupported();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.danceCodeScreenTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.danceCodeTooLong,
                    key: const ValueKey('dance-code-too-long'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Builder(
                    builder: (context) => FilledButton.icon(
                      key: const ValueKey('dance-code-share-file'),
                      onPressed: () {
                        final box = context.findRenderObject() as RenderBox?;
                        onShareFile(
                          box != null && box.hasSize
                              ? box.localToGlobal(Offset.zero) & box.size
                              : null,
                        );
                      },
                      icon: Icon(
                        unsupported
                            ? Icons.save_alt_outlined
                            : Icons.share_outlined,
                      ),
                      label: Text(
                        unsupported
                            ? l10n.exportSaveDanceBundle
                            : l10n.exportShareDanceBundle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
