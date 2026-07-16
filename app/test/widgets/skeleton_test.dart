import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/widgets/skeleton.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool reduceMotion,
}) async {
  final notifier = ValueNotifier<bool>(reduceMotion);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ReduceMotionScope(
        notifier: notifier,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('SkeletonListView exposes a single "Loading…" semantics label', (
    tester,
  ) async {
    // Reduce motion keeps the skeleton static so pumpAndSettle is safe.
    await _pump(tester, const SkeletonListView(), reduceMotion: true);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Loading\u2026'), findsOneWidget);
    expect(find.byType(SkeletonBone), findsWidgets);
  });

  testWidgets('SkeletonDetailView exposes a "Loading…" semantics label', (
    tester,
  ) async {
    await _pump(tester, const SkeletonDetailView(), reduceMotion: true);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Loading\u2026'), findsOneWidget);
  });

  testWidgets('Shimmer is static (no ShaderMask) when Reduce motion is on', (
    tester,
  ) async {
    await _pump(tester, const SkeletonListView(), reduceMotion: true);
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('Shimmer animates (ShaderMask present) when motion is allowed', (
    tester,
  ) async {
    await _pump(tester, const SkeletonListView(), reduceMotion: false);
    // A single frame — the shimmer repeats, so avoid pumpAndSettle here.
    await tester.pump();

    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.bySemanticsLabel('Loading\u2026'), findsOneWidget);
  });
}
