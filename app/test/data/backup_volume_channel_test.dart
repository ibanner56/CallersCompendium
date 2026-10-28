import 'package:compendium_app/src/data/backup_volume_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(BackupVolumeChannel.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the native side about the path and returns its answer', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 123456789;
    });

    expect(await BackupVolumeChannel().availableBytes('/a/b.json'), 123456789);
    expect(calls.single.method, 'availableBytes');
    expect(calls.single.arguments, '/a/b.json');
  });

  test('a null answer stays unknown', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await BackupVolumeChannel().availableBytes('/a'), isNull);
  });

  test('a platform with no native side reads as unknown', () async {
    expect(await BackupVolumeChannel().availableBytes('/a'), isNull);
  });

  test('a native failure reads as unknown', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'statfs'),
    );
    expect(await BackupVolumeChannel().availableBytes('/a'), isNull);
  });
}
