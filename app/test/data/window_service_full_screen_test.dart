import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/window_frame.dart';
import 'package:compendium_app/src/data/window_service.dart';

/// Records [set] calls; nothing else is reached by the listener paths tested.
class _RecordingSettings implements SettingsRepository {
  final List<Object?> frames = <Object?>[];

  @override
  Future<void> set(String key, Object? value, {DateTime? at}) async {
    if (key == kWindowFrameKey) frames.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _channel = MethodChannel('window_manager');
const _fullScreenBounds = <String, double>{
  'x': 0,
  'y': 0,
  'width': 2560,
  'height': 1440,
};
const _ordinaryBounds = <String, double>{
  'x': 100,
  'y': 80,
  'width': 1200,
  'height': 900,
};

/// PLAT-9: Perform's full-screen toggle resizes the window to the display,
/// and the frame persisted meanwhile is what the next launch reopens at.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `WindowService` acts only on the desktop platforms; the suite runs on a
  // Linux host in CI, so these tests exercise it there and skip elsewhere.
  final skip = !isDesktopWindowPlatform;

  late _RecordingSettings settings;
  late WindowService service;
  late bool platformFullScreen;
  late Map<String, double> bounds;

  setUp(() {
    settings = _RecordingSettings();
    service = WindowService(settings);
    platformFullScreen = false;
    bounds = _ordinaryBounds;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return switch (call.method) {
            'isFullScreen' => platformFullScreen,
            'isMaximized' => false,
            'getBounds' => bounds,
            _ => null,
          };
        });
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  testWidgets('a resize persists the frame', (tester) async {
    service.onWindowResized();
    await settle(tester);
    expect(settings.frames, hasLength(1));
    expect(WindowFrame.fromJson(settings.frames.single)!.width, 1200);
  }, skip: skip);

  testWidgets('nothing is persisted while the window is full screen', (
    tester,
  ) async {
    service.onWindowEnterFullScreen();
    platformFullScreen = true;
    bounds = _fullScreenBounds;
    service.onWindowResized();
    service.onWindowMoved();
    service.onWindowMaximize();
    service.onWindowUnmaximize();
    await settle(tester);
    expect(settings.frames, isEmpty);

    // Leaving persists the ordinary frame the window returns to.
    platformFullScreen = false;
    bounds = _ordinaryBounds;
    service.onWindowLeaveFullScreen();
    await settle(tester);
    expect(settings.frames, hasLength(1));
    expect(WindowFrame.fromJson(settings.frames.single)!.width, 1200);
  }, skip: skip);

  testWidgets('a resize already pending when full screen begins is dropped', (
    tester,
  ) async {
    service.onWindowResized();
    service.onWindowEnterFullScreen();
    platformFullScreen = true;
    bounds = _fullScreenBounds;
    await settle(tester);
    expect(settings.frames, isEmpty);
  }, skip: skip);

  testWidgets('a full-screen window is not persisted without the event', (
    tester,
  ) async {
    // The resize can land before the enter event does, or the event may never
    // come; the plugin's own answer still keeps the display's bounds out.
    platformFullScreen = true;
    bounds = _fullScreenBounds;
    service.onWindowResized();
    await settle(tester);
    expect(settings.frames, isEmpty);
  }, skip: skip);
}
