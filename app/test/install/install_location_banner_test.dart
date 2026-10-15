import 'package:compendium_app/src/install/install_location_banner.dart';
import 'package:compendium_app/src/install/install_location_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

const _banner = ValueKey('install-location-banner');
const _channel = MethodChannel(InstallLocationChannel.channelName);

/// Answers the native check with [answer], or throws it when it is an
/// exception. Returns a counter of how many times the check was asked.
ValueNotifier<int> _mockNative(WidgetTester tester, Object? answer) {
  final calls = ValueNotifier<int>(0);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    expect(call.method, 'isRunningUninstalled');
    calls.value++;
    if (answer is Exception) throw answer;
    return answer;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    ),
  );
  addTearDown(calls.dispose);
  return calls;
}

Future<void> _pump(WidgetTester tester, TargetPlatform platform) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: InstallLocationBanner(platform: platform)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('macOS run from the disk image shows the notice', (tester) async {
    final calls = _mockNative(tester, true);
    await _pump(tester, TargetPlatform.macOS);

    expect(calls.value, 1);
    expect(find.byKey(_banner), findsOneWidget);
    expect(find.textContaining("isn't installed yet"), findsOneWidget);
  });

  testWidgets('Dismiss hides the notice', (tester) async {
    _mockNative(tester, true);
    await _pump(tester, TargetPlatform.macOS);

    await tester.tap(
      find.byKey(const ValueKey('install-location-banner-dismiss')),
    );
    await tester.pump();
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('macOS run from Applications shows nothing', (tester) async {
    final calls = _mockNative(tester, false);
    await _pump(tester, TargetPlatform.macOS);

    expect(calls.value, 1);
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('a native error shows nothing', (tester) async {
    final calls = _mockNative(tester, PlatformException(code: 'boom'));
    await _pump(tester, TargetPlatform.macOS);

    expect(calls.value, 1);
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('no native implementation shows nothing', (tester) async {
    await _pump(tester, TargetPlatform.macOS);
    expect(find.byKey(_banner), findsNothing);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets('${platform.name} never asks and shows nothing', (
      tester,
    ) async {
      final calls = _mockNative(tester, true);
      await _pump(tester, platform);

      expect(calls.value, 0);
      expect(find.byKey(_banner), findsNothing);
    });
  }
}
