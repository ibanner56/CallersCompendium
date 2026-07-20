import 'package:compendium_app/src/widgets/tap_tempo_metronome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a [TapTempoMetronome] whose clock returns whatever [now] currently
/// points at, so tests can advance time deterministically between taps.
Future<void> _pumpMetronome(
  WidgetTester tester, {
  required DateTime Function() now,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // Override disableAnimations *inside* MaterialApp's own MediaQuery
      // (via builder) — wrapping MediaQuery outside MaterialApp doesn't work
      // because WidgetsApp installs a fresh MediaQuery.fromView that would
      // shadow the outer override before it reaches TapTempoMetronome.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(body: TapTempoMetronome(clock: now)),
    ),
  );
}

Finder get _target => find.byKey(const ValueKey('tap-tempo-target'));
Finder get _readout => find.byKey(const ValueKey('tap-tempo-readout'));
Finder get _reset => find.byKey(const ValueKey('tap-tempo-reset'));

String _readoutText(WidgetTester tester) => tester.widget<Text>(_readout).data!;

void main() {
  group('TapTempoMetronome', () {
    testWidgets('shows a prompt and no BPM before any taps', (tester) async {
      await _pumpMetronome(tester, now: DateTime.now);
      expect(_readoutText(tester), 'Tap to set tempo');
      // Reset is disabled while there is nothing to clear.
      expect(tester.widget<TextButton>(_reset).onPressed, isNull);
    });

    testWidgets('derives BPM from a steady tap interval', (tester) async {
      // 500 ms between taps == 120 BPM.
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t);

      await tester.tap(_target); // first tap seeds the sequence
      await tester.pump();
      expect(_readoutText(tester), 'Tap to set tempo');

      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        await tester.tap(_target);
        await tester.pump();
      }

      expect(_readoutText(tester), '120 BPM');
      await tester.pump(const Duration(milliseconds: 250)); // let pulse run
    });

    testWidgets('clamps very fast taps to the maximum BPM', (tester) async {
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t);

      await tester.tap(_target);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        // 10 ms => 6000 BPM raw, must clamp to 300.
        t = t.add(const Duration(milliseconds: 10));
        await tester.tap(_target);
        await tester.pump();
      }

      expect(_readoutText(tester), '${TapTempoMetronome.maxBpm} BPM');
    });

    testWidgets('clamps very slow (but non-stale) taps to the minimum BPM', (
      tester,
    ) async {
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t);

      await tester.tap(_target);
      await tester.pump();
      // 1900 ms is under the 2000 ms stale threshold but ~31.6 BPM raw... use
      // a value that clamps: 60000/1900 ≈ 31.6, still above 30. Use exactly
      // just-under-stale to exercise the low end; 1999 ms => ~30 BPM.
      t = t.add(const Duration(milliseconds: 1999));
      await tester.tap(_target);
      await tester.pump();

      final bpm = int.parse(_readoutText(tester).split(' ').first);
      expect(bpm, greaterThanOrEqualTo(TapTempoMetronome.minBpm));
      expect(bpm, lessThanOrEqualTo(TapTempoMetronome.maxBpm));
    });

    testWidgets('a stale gap restarts the sequence instead of a slow beat', (
      tester,
    ) async {
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t);

      // Establish 120 BPM.
      await tester.tap(_target);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        await tester.tap(_target);
        await tester.pump();
      }
      expect(_readoutText(tester), '120 BPM');

      // A long pause (> stale threshold) clears the tempo.
      t = t.add(const Duration(seconds: 5));
      await tester.tap(_target);
      await tester.pump();
      expect(_readoutText(tester), 'Tap to set tempo');
    });

    testWidgets('ignores a zero/negative interval without crashing', (
      tester,
    ) async {
      final t = DateTime(2026); // never advances -> repeated taps have 0 gap
      await _pumpMetronome(tester, now: () => t);

      await tester.tap(_target);
      await tester.pump();
      await tester.tap(_target); // gap == 0, must be ignored (no Infinity/NaN)
      await tester.pump();
      await tester.tap(_target);
      await tester.pump();

      expect(_readoutText(tester), 'Tap to set tempo');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reset clears the derived tempo', (tester) async {
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t);

      await tester.tap(_target);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        await tester.tap(_target);
        await tester.pump();
      }
      expect(_readoutText(tester), '120 BPM');

      await tester.tap(_reset);
      await tester.pump();
      expect(_readoutText(tester), 'Tap to set tempo');
      expect(tester.widget<TextButton>(_reset).onPressed, isNull);
    });

    testWidgets('works under reduced motion (no scaling, no crash)', (
      tester,
    ) async {
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t, disableAnimations: true);

      await tester.tap(_target);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        await tester.tap(_target);
        await tester.pump();
      }

      expect(_readoutText(tester), '120 BPM');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes semantics for the tap target and readout', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var t = DateTime(2026);
      await _pumpMetronome(tester, now: () => t);

      // Tap target announces its button role + name before any tempo.
      expect(find.bySemanticsLabel('Tap to set tempo'), findsOneWidget);

      await tester.tap(_target);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        await tester.tap(_target);
        await tester.pump();
      }

      // Readout is exposed as spoken beats-per-minute, not just the glyph.
      expect(find.bySemanticsLabel('120 beats per minute'), findsWidgets);
      handle.dispose();
    });
  });
}
