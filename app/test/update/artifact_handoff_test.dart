import 'dart:io';

import 'package:compendium_app/src/update/artifact_handoff.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [ProcessRunner] that records every command instead of launching it, so we
/// can assert exactly what the handoff would run without launching anything.
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

/// A [ProcessRunner] whose launch methods throw, simulating a caller that
/// invokes the runner outside the handoff's own try/catch. Proves the handoff
/// stays fail-closed (→ [HandoffResult.failed]) even if a runner throws.
class _ThrowingRunner extends ProcessRunner {
  const _ThrowingRunner();

  @override
  Future<bool> runToCompletion(String executable, List<String> arguments) {
    throw const ProcessException('boom', []);
  }

  @override
  Future<bool> startDetached(String executable, List<String> arguments) {
    throw const ProcessException('boom', []);
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

  test('Windows starts the verified installer directly', () async {
    final exe = File('${tempDir.path}/CallersCompendium-Setup.exe')
      ..writeAsStringSync('fake');
    final runner = _RecordingRunner();
    final result = await handoffArtifactToOs(
      exe,
      UpdatePlatform.windows,
      runner: runner,
    );
    expect(result, HandoffResult.launched);
    expect(runner.startCalls, [
      [exe.path],
    ]);
    expect(runner.runCalls, isEmpty);
  });

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

  group('ProcessRunner fail-closed contract', () {
    // A path that cannot be an executable, so Process.run/Process.start throws
    // a ProcessException. The base ProcessRunner must catch it and return false
    // (not let it escape) so the documented contract holds outside a caller's
    // own try/catch.
    final bogusExecutable =
        '${Directory.systemTemp.path}/definitely-not-an-executable-431';

    test('runToCompletion returns false when the executable throws', () async {
      const runner = ProcessRunner();
      expect(await runner.runToCompletion(bogusExecutable, const []), isFalse);
    });

    test('startDetached returns false when the executable throws', () async {
      const runner = ProcessRunner();
      expect(await runner.startDetached(bogusExecutable, const []), isFalse);
    });

    test('handoff reports failed when the runner throws (macOS)', () async {
      const runner = _ThrowingRunner();
      expect(
        await handoffArtifactToOs(
          installer,
          UpdatePlatform.macos,
          runner: runner,
        ),
        HandoffResult.failed,
      );
    });

    test('handoff reports failed when the runner throws (Linux)', () async {
      const runner = _ThrowingRunner();
      expect(
        await handoffArtifactToOs(
          installer,
          UpdatePlatform.linux,
          runner: runner,
        ),
        HandoffResult.failed,
      );
    });
  });
}
