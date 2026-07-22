import 'dart:io';

import 'package:compendium_app/src/data/single_instance_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A fake [InstanceLockHandle] that records whether it was released.
class _FakeHandle implements InstanceLockHandle {
  bool released = false;

  @override
  Future<void> release() async => released = true;
}

/// A fake [InstanceLockPrimitive] with a scripted outcome, so the guard's
/// decision logic is exercised without a real OS lock — a real advisory lock
/// can't be contended within one process on POSIX, so this stands in for
/// "another live process already holds it" and for an unexpected IO fault.
class _FakePrimitive implements InstanceLockPrimitive {
  _FakePrimitive.acquired() : _handle = _FakeHandle();
  _FakePrimitive.alreadyRunning() : _handle = null;
  _FakePrimitive.throwing() : _handle = null, _throw = true;

  final _FakeHandle? _handle;
  bool _throw = false;
  File? lastLockFile;

  @override
  Future<InstanceLockHandle?> tryAcquire(File lockFile) async {
    lastLockFile = lockFile;
    if (_throw) {
      throw const FileSystemException('injected IO fault');
    }
    return _handle;
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('single_instance_guard_');
  });

  tearDown(() async {
    // Release any process-wide lock a test acquired so the temp dir can be
    // deleted (an open, locked handle can block deletion on some platforms) and
    // so shared static state never leaks between tests.
    await DesktopSingleInstance.releaseHeld();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DesktopSingleInstance guardWith({
    InstanceLockPrimitive primitive = const AdvisoryFileLock(),
  }) => DesktopSingleInstance(
    lockDirectoryProvider: () async => dir,
    primitive: primitive,
  );

  File lockFile() => File(p.join(dir.path, kSingleInstanceLockFileName));

  group('acquire (real advisory lock)', () {
    test('first acquire succeeds and creates the lock file', () async {
      final result = await guardWith().acquire();

      expect(result, SingleInstanceResult.acquired);
      expect(await lockFile().exists(), isTrue);
    });

    test('release frees the lock so a later acquire succeeds again', () async {
      expect(await guardWith().acquire(), SingleInstanceResult.acquired);

      // Releasing stands in for the OS releasing the lock at process exit.
      await DesktopSingleInstance.releaseHeld();

      expect(await guardWith().acquire(), SingleInstanceResult.acquired);
    });

    test(
      'a stale lock file left by a crashed instance does not block launch',
      () async {
        // Simulate a leftover lock file (with stale PID content) from a process
        // that died: the OS releases advisory locks on death, so only the inert
        // file remains. A fresh launch must still acquire.
        await lockFile().writeAsString('999999\n');

        final result = await guardWith().acquire();

        expect(result, SingleInstanceResult.acquired);
      },
    );
  });

  group('acquire (decision logic via fake primitive)', () {
    test('reports acquired when the primitive grants the lock', () async {
      final primitive = _FakePrimitive.acquired();

      final result = await guardWith(primitive: primitive).acquire();

      expect(result, SingleInstanceResult.acquired);
      // The lock is resolved inside the injected directory, never a shared
      // world-writable temp path.
      expect(
        primitive.lastLockFile!.path,
        p.join(dir.path, kSingleInstanceLockFileName),
      );
    });

    test(
      'reports alreadyRunning when another instance holds the lock',
      () async {
        final result = await guardWith(
          primitive: _FakePrimitive.alreadyRunning(),
        ).acquire();

        expect(result, SingleInstanceResult.alreadyRunning);
      },
    );

    test(
      'fails open (unavailable, no throw) on an unexpected IO fault',
      () async {
        final result = await guardWith(
          primitive: _FakePrimitive.throwing(),
        ).acquire();

        expect(result, SingleInstanceResult.unavailable);
      },
    );

    test('fails open when the lock directory cannot be resolved', () async {
      final guard = DesktopSingleInstance(
        lockDirectoryProvider: () async =>
            throw const FileSystemException('no support dir'),
      );

      expect(await guard.acquire(), SingleInstanceResult.unavailable);
    });
  });
}
