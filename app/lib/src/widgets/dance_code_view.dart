import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../export/dance_code.dart';
import '../export/share_file.dart';
import '../screens/perform_wakelock.dart';
import 'brand_mark.dart';

/// How much of the code's width the brand mark covers (#2334). The issue asks
/// for about 15 to 20%. Only a level H code (30% of it can be lost) is drawn
/// with the mark, and `dance_code_view_test.dart` decodes a rendered one to
/// show it still scans.
const double kDanceCodeMarkFraction = 0.18;

/// The white square the mark sits in, as a multiple of the mark's own size.
const double _clearZoneFactor = 1.18;

/// A QR code needs a quiet zone of at least this many modules on each side.
const int _quietZoneModules = 4;

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
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final available = constraints.biggest.shortestSide;
                      final span = plan.moduleCount + 2 * _quietZoneModules;
                      // Whole device pixels per module: a scanner reads a
                      // blurred edge worse than a crisp one.
                      final modulePixels = (available * dpr / span)
                          .floor()
                          .clamp(1, 1 << 20);
                      final module = modulePixels / dpr;
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
      color: Colors.white,
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
                color: Colors.white,
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

class _CodePainter extends CustomPainter {
  _CodePainter(this.modules, this.module, this.quietZone);

  final Path modules;
  final double module;
  final int quietZone;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..translate(quietZone * module, quietZone * module)
      ..scale(module);
    // No anti-aliasing: every edge sits on a whole device pixel.
    canvas.drawPath(
      modules,
      Paint()
        ..color = Colors.black
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

  /// Starts the dance-file share or save.
  final VoidCallback onShareFile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unsupported = isBundleShareUnsupported();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.danceCodeScreenTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 16),
                  Text(
                    l10n.danceCodeTooLong,
                    key: const ValueKey('dance-code-too-long'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const ValueKey('dance-code-share-file'),
                    onPressed: onShareFile,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
