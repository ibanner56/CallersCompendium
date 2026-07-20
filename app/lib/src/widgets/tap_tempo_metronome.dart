import 'package:flutter/material.dart';

/// A self-contained, opt-in **tap-tempo visual metronome** for Perform mode
/// (issue #366, PM-scoped slice). The caller taps out the beat on a large
/// target; we derive the tempo (BPM) from a rolling average of recent tap
/// intervals and drive a visual pulse the caller can follow / hold up to
/// communicate tempo to a band.
///
/// Deliberately minimal per the approved scope:
/// * **No audio** — this is a *visual* metronome only (no audio dependency).
/// * **No persistence** — BPM is ephemeral in-view state; nothing is written to
///   the dance/program model.
/// * **No auto-detection** — tempo comes only from the caller's taps.
///
/// The pulse is driven by a single reused [AnimationController] (a [Ticker]),
/// independent of the Perform screens' elapsed-clock `Timer.periodic`. The
/// controller is created once and only *rescheduled* (duration changed +
/// restarted) when the BPM changes, so mid-run tempo changes never leak
/// tickers. It is disposed with the widget.
class TapTempoMetronome extends StatefulWidget {
  const TapTempoMetronome({super.key, this.clock = _systemNow});

  /// Time source for tap intervals. Defaults to the wall clock; overridden in
  /// tests to make derived BPM deterministic.
  final DateTime Function() clock;

  /// Rolling window of the most recent tap intervals averaged into the BPM.
  static const int windowSize = 6;

  /// Gaps longer than this (i.e. slower than [minBpm]) are treated as the start
  /// of a fresh tap sequence rather than a very slow beat.
  static const int staleThresholdMs = 2000;

  /// Sensible tempo bounds. Derived BPM is clamped into this range.
  static const int minBpm = 30;
  static const int maxBpm = 300;

  @override
  State<TapTempoMetronome> createState() => _TapTempoMetronomeState();
}

/// Default wall-clock time source (a top-level function so it can be a `const`
/// constructor default).
DateTime _systemNow() => DateTime.now();

class _TapTempoMetronomeState extends State<TapTempoMetronome>
    with SingleTickerProviderStateMixin {
  /// Most recent inter-tap intervals in milliseconds (max [windowSize]).
  final List<int> _intervalsMs = <int>[];

  /// Timestamp of the previous tap, used to measure the next interval.
  DateTime? _lastTap;

  /// Derived tempo, or null until at least two valid taps have been recorded.
  int? _bpm;

  /// Single reused pulse clock. Duration is set to the beat interval and the
  /// controller repeats; it is never recreated on tempo change.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _handleTap() {
    final now = widget.clock();
    final last = _lastTap;
    _lastTap = now;

    if (last == null) {
      // First tap of a sequence: nothing to average yet.
      setState(() {});
      return;
    }

    final gapMs = now.difference(last).inMilliseconds;

    // Guard degenerate math: a non-positive gap (rapid double-tap within the
    // same millisecond, or a clock that didn't advance) would yield an infinite
    // / NaN BPM, so ignore it entirely.
    if (gapMs <= 0) {
      return;
    }

    // A long pause means the caller is starting over at a new tempo — discard
    // the stale window and let this tap seed a fresh sequence.
    if (gapMs > TapTempoMetronome.staleThresholdMs) {
      setState(() {
        _intervalsMs.clear();
        _bpm = null;
        _pulse.stop();
        _pulse.reset();
      });
      return;
    }

    _intervalsMs.add(gapMs);
    while (_intervalsMs.length > TapTempoMetronome.windowSize) {
      _intervalsMs.removeAt(0);
    }
    _recomputeBpm();
  }

  void _recomputeBpm() {
    if (_intervalsMs.isEmpty) {
      setState(() {
        _bpm = null;
        _pulse.stop();
        _pulse.reset();
      });
      return;
    }

    final total = _intervalsMs.fold<int>(0, (sum, ms) => sum + ms);
    final meanMs = total / _intervalsMs.length;

    // Defensive: mean can only be > 0 here (all intervals are > 0), but guard
    // against division by zero regardless so we never emit Infinity/NaN.
    if (meanMs <= 0) {
      return;
    }

    final rawBpm = (60000 / meanMs).round();
    final bpm = rawBpm.clamp(
      TapTempoMetronome.minBpm,
      TapTempoMetronome.maxBpm,
    );

    setState(() {
      _bpm = bpm;
      _reschedulePulse(bpm);
    });
  }

  /// Point the (already-created) pulse controller at the new beat interval and
  /// restart it. Reusing the controller — rather than creating a new one —
  /// means changing tempo mid-run cannot leak tickers.
  void _reschedulePulse(int bpm) {
    final beatMs = (60000 / bpm).round().clamp(1, 60000);
    _pulse
      ..stop()
      ..duration = Duration(milliseconds: beatMs)
      ..value = 0
      ..repeat();
  }

  void _reset() {
    setState(() {
      _intervalsMs.clear();
      _lastTap = null;
      _bpm = null;
      _pulse.stop();
      _pulse.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bpm = _bpm;
    final hasTempo = bpm != null;

    final readout = hasTempo ? '$bpm BPM' : 'Tap to set tempo';
    final readoutSemantics = hasTempo
        ? '$bpm beats per minute'
        : 'No tempo set yet. Tap the target to set a tempo.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.av_timer, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Tap tempo', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 20),
          // Large, labelled tap target with the pulsing visual inside.
          Semantics(
            button: true,
            label: 'Tap to set tempo',
            value: hasTempo ? '$bpm beats per minute' : null,
            onTapHint: 'record a beat',
            child: _TapTarget(
              key: const ValueKey('tap-tempo-target'),
              controller: _pulse,
              reduceMotion: reduceMotion,
              bpm: bpm,
              onTap: _handleTap,
            ),
          ),
          const SizedBox(height: 20),
          // Text readout — never conveyed by the pulse's motion/colour alone
          // (WCAG 1.4.1): the numeric tempo is always spelled out here.
          Semantics(
            liveRegion: true,
            label: readoutSemantics,
            excludeSemantics: true,
            child: Text(
              readout,
              key: const ValueKey('tap-tempo-readout'),
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasTempo
                ? 'Keep tapping to refine · Reset to start over'
                : 'Tap at least twice in time with the beat',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const ValueKey('tap-tempo-reset'),
            onPressed: (_intervalsMs.isEmpty && _lastTap == null)
                ? null
                : _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

/// The circular tap surface plus its beat visual. In normal mode the inner
/// shape scales on each beat; under reduced motion it swaps to a discrete
/// on-beat fill step (no scaling). Either way the beat is conveyed by SHAPE +
/// (motion or fill step) + the sibling text readout — never colour alone.
class _TapTarget extends StatelessWidget {
  const _TapTarget({
    super.key,
    required this.controller,
    required this.reduceMotion,
    required this.bpm,
    required this.onTap,
  });

  final AnimationController controller;
  final bool reduceMotion;
  final int? bpm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 180.0;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outline, width: 2),
          ),
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final active = bpm != null && controller.isAnimating;

              if (reduceMotion) {
                // Discrete on-beat fill step: filled for the first half of each
                // beat, hollow for the second — no scaling/motion.
                final onBeat = active && controller.value < 0.5;
                return Container(
                  width: size * 0.55,
                  height: size * 0.55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onBeat
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.2),
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: child,
                );
              }

              // Motion mode: pop at the start of each beat, ease back to rest.
              final t = Curves.easeOut.transform(controller.value);
              final scale = active ? 1.0 + 0.35 * (1 - t) : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: size * 0.55,
                  height: size * 0.55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.15),
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            },
            child: bpm == null
                ? Icon(Icons.touch_app, size: 40, color: scheme.primary)
                : Text(
                    '$bpm',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
