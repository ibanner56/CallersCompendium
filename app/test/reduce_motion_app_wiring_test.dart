import 'dart:ui' show AccessibilityFeatures;

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';

/// The in-app Reduce motion switch (PRES-14) has to reach what the framework
/// reads, not only the widgets that ask [ReduceMotionScope]: the app's
/// `MediaQuery.disableAnimations` and the theme cross-fade.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MaterialApp> pumpApp(
    WidgetTester tester, {
    required bool? override,
    required bool osReducesMotion,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: osReducesMotion);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final appData = openTestAppData();
    if (override != null) {
      await appData.repositories.settings.set(kReduceMotionKey, override);
    }
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
      ),
    );
    // Not pumpAndSettle: with motion allowed the ready app keeps a looping
    // animation running, which never settles.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return tester.widget<MaterialApp>(find.byType(MaterialApp));
  }

  bool disableAnimationsBelowApp(WidgetTester tester) => MediaQuery.of(
    tester.element(find.byType(Navigator).first),
  ).disableAnimations;

  testWidgets('"on" reaches MediaQuery and turns the theme cross-fade off', (
    tester,
  ) async {
    final app = await pumpApp(tester, override: true, osReducesMotion: false);

    expect(disableAnimationsBelowApp(tester), isTrue);
    expect(app.themeAnimationStyle, AnimationStyle.noAnimation);
  });

  testWidgets('"off" beats an OS that asks for reduced motion', (tester) async {
    await pumpApp(tester, override: false, osReducesMotion: true);

    expect(disableAnimationsBelowApp(tester), isFalse);
  });

  testWidgets('unset follows the OS and leaves the cross-fade alone', (
    tester,
  ) async {
    final app = await pumpApp(tester, override: null, osReducesMotion: true);

    expect(disableAnimationsBelowApp(tester), isTrue);
    expect(app.themeAnimationStyle, isNull);
  });
}

class FakeAccessibilityFeatures implements AccessibilityFeatures {
  const FakeAccessibilityFeatures({required this.disableAnimations});

  @override
  final bool disableAnimations;

  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}
