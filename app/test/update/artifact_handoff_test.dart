import 'dart:io';

import 'package:compendium_app/src/update/artifact_handoff.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [ProcessRunner] that records every command instead of launching it, so we
/// can assert exactly what the handoff would run (and that Windows/Linux are
/// only ever *revealed*, never executed).
class _RecordingRunner extends ProcessRunner {
  _RecordingRunner({this.succeed = true});

  final bool succeed;
  final List<List<String>> runCalls = [];
  final List<List<String>> startCalls = [];

  @override
  Future<bool> runToCompletion(
    String executable,
    List<String> arguments,
  ) async {
    runCalls.add([executable, ...arguments]);
    return succeed;
  }

  @override
  Future<bool> startDetached(String executable, List<String> arguments) async {
    startCalls.add([executable, ...arguments]);
    return succeed;
  }
}

void main() {
  late Directory tempDir;
  late File installer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('handoff_test_');
    installer = File('${tempDir.path}/CallersCompendium-0.2.0.dmg')
      ..writeAsStringSync('fake');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('macOS launches via `open` and reports launched', () async {
    final runner = _RecordingRunner();
    final result = await handoffArtifactToOs(
      installer,
      UpdatePlatform.macos,
      runner: runner,
    );
    expect(result, HandoffResult.launched);
    expect(runner.runCalls, [
      ['open', installer.path],
    ]);
    expect(runner.startCalls, isEmpty);
  });

  test(
    'Windows reveals in Explorer and never executes the installer',
    () async {
      final exe = File('${tempDir.path}/CallersCompendium-Setup.exe')
        ..writeAsStringSync('fake');
      final runner = _RecordingRunner();
      final result = await handoffArtifactToOs(
        exe,
        UpdatePlatform.windows,
        runner: runner,
      );
      expect(result, HandoffResult.revealed);
      // Only a reveal (explorer /select), never a direct launch of the .exe.
      expect(runner.startCalls, [
        ['explorer.exe', '/select,${exe.path}'],
      ]);
      expect(runner.runCalls, isEmpty);
      // Defensive: the installer path is never itself an executable we started.
      expect(runner.startCalls.every((c) => c.first != exe.path), isTrue);
    },
  );

  test(
    'Linux reveals the folder, never chmods or launches the AppImage',
    () async {
      final appImage = File('${tempDir.path}/CallersCompendium-0.2.0.AppImage')
        ..writeAsStringSync('fake');
      final runner = _RecordingRunner();
      final result = await handoffArtifactToOs(
        appImage,
        UpdatePlatform.linux,
        runner: runner,
      );
      expect(result, HandoffResult.revealed);
      // Reveal the containing folder only.
      expect(runner.startCalls, [
        ['xdg-open', tempDir.path],
      ]);
      expect(runner.runCalls, isEmpty);
      // No chmod, and the AppImage is never executed directly.
      final allCommands = [...runner.startCalls, ...runner.runCalls];
      expect(allCommands.any((c) => c.first == 'chmod'), isFalse);
      expect(allCommands.any((c) => c.first == appImage.path), isFalse);
    },
  );

  test('a failed launch command reports failed (macOS)', () async {
    final runner = _RecordingRunner(succeed: false);
    final result = await handoffArtifactToOs(
      installer,
      UpdatePlatform.macos,
      runner: runner,
    );
    expect(result, HandoffResult.failed);
  });

  test('a failed reveal command reports failed (Linux)', () async {
    final runner = _RecordingRunner(succeed: false);
    final result = await handoffArtifactToOs(
      installer,
      UpdatePlatform.linux,
      runner: runner,
    );
    expect(result, HandoffResult.failed);
  });

  test('mobile platforms never hand off', () async {
    final runner = _RecordingRunner();
    expect(
      await handoffArtifactToOs(
        installer,
        UpdatePlatform.android,
        runner: runner,
      ),
      HandoffResult.failed,
    );
    expect(
      await handoffArtifactToOs(installer, UpdatePlatform.ios, runner: runner),
      HandoffResult.failed,
    );
    expect(runner.runCalls, isEmpty);
    expect(runner.startCalls, isEmpty);
  });
}
