import 'dart:async';
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

/// Records raise requests and listens without any socket.
class _FakeRaiseChannel implements InstanceRaiseChannel {
  _FakeRaiseChannel({this.raiseResult = true, this.listenThrows = false});

  final bool raiseResult;
  final bool listenThrows;
  final List<Directory> raiseRequests = [];
  final List<Directory> listens = [];
  void Function()? onRaise;

  @override
  Future<int> listen(Directory lockDir, void Function() onRaise) async {
    if (listenThrows) throw const FileSystemException('injected listen fault');
    listens.add(lockDir);
    this.onRaise = onRaise;
    return 1;
  }

  @override
  Future<bool> requestRaise(Directory lockDir) async {
    raiseRequests.add(lockDir);
    return raiseResult;
  }

  @override
  Future<void> close() async {}
}

/// An [IOSink] that captures what is written to it.
class _CaptureSink implements IOSink {
  final StringBuffer buffer = StringBuffer();

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
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
    InstanceRaiseChannel? raiseChannel,
    bool listensForRaise = true,
  }) => DesktopSingleInstance(
    lockDirectoryProvider: () async => dir,
    primitive: primitive,
    raiseChannel: raiseChannel,
    listensForRaise: listensForRaise,
  );

  File lockFile() => File(p.join(dir.path, kSingleInstanceLockFileName));

  /// The errno/OS code the current platform reports for genuine lock
  /// contention (EAGAIN/EWOULDBLOCK; ERROR_LOCK_VIOLATION on Windows), so the
  /// contention tests stay portable across the CI matrix.
  int platformContentionCode() {
    if (Platform.isWindows) return 33; // ERROR_LOCK_VIOLATION
    if (Platform.isMacOS) return 35; // EAGAIN / EWOULDBLOCK (Darwin)
    return 11; // EAGAIN / EWOULDBLOCK (Linux)
  }

  /// A real [AdvisoryFileLock] whose lock call fails with [error], so the
  /// contention-vs-unexpected-fault classification is exercised end-to-end
  /// without a real second process.
  AdvisoryFileLock lockFailingWith(FileSystemException error) =>
      AdvisoryFileLock(lockOverride: (_) async => throw error);

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

  group('contention vs. unexpected lock failure (real AdvisoryFileLock)', () {
    test(
      'genuine OS contention maps to alreadyRunning (refuse 2nd instance)',
      () async {
        final guard = guardWith(
          primitive: lockFailingWith(
            FileSystemException(
              'resource temporarily unavailable',
              lockFile().path,
              OSError('EAGAIN', platformContentionCode()),
            ),
          ),
        );

        expect(await guard.acquire(), SingleInstanceResult.alreadyRunning);
      },
    );

    test('EACCES is treated as contention on POSIX', () async {
      // Skipped on Windows, where contention uses distinct codes (32/33).
      final primitive = lockFailingWith(
        FileSystemException(
          'permission denied',
          lockFile().path,
          const OSError('EACCES', 13),
        ),
      );

      expect(await primitive.tryAcquire(lockFile()), isNull);
    }, skip: Platform.isWindows);

    test(
      'a non-contention lock failure FAILS OPEN (unavailable), not closed',
      () async {
        // e.g. a filesystem that does not support advisory locking (ENOSYS 38):
        // must NOT be misread as "already running" (which would brick launch).
        final guard = guardWith(
          primitive: lockFailingWith(
            const FileSystemException(
              'function not implemented',
              '',
              OSError('ENOSYS', 38),
            ),
          ),
        );

        expect(await guard.acquire(), SingleInstanceResult.unavailable);
      },
    );

    test('a lock failure with no OSError fails open (rethrows)', () async {
      final primitive = lockFailingWith(
        const FileSystemException('opaque lock failure'),
      );

      await expectLater(
        primitive.tryAcquire(lockFile()),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('classifier: unrecognized errno is not contention', () {
      expect(isAdvisoryLockContention(const OSError('ENOSPC', 28)), isFalse);
      expect(isAdvisoryLockContention(null), isFalse);
      expect(
        isAdvisoryLockContention(OSError('EAGAIN', platformContentionCode())),
        isTrue,
      );
    });
  });
  group('handleSecondLaunch', () {
    test(
      'the second launch sends a raise request when another instance holds the '
      'lock',
      () async {
        final channel = _FakeRaiseChannel();
        final err = _CaptureSink();

        final outcome = await handleSecondLaunch(
          guardWith(
            primitive: _FakePrimitive.alreadyRunning(),
            raiseChannel: channel,
          ),
          onRaise: () {},
          err: err,
        );

        expect(outcome, SecondLaunchOutcome.exitNow);
        expect(channel.raiseRequests, hasLength(1));
        expect(channel.raiseRequests.single.path, dir.path);
        expect(channel.listens, isEmpty);
        expect(err.buffer.toString(), contains('bring its window forward'));
      },
    );

    test('a platform without the raise listener (macOS) acquires and proceeds '
        'without binding a socket', () async {
      final channel = _FakeRaiseChannel();

      final outcome = await handleSecondLaunch(
        guardWith(
          primitive: _FakePrimitive.acquired(),
          raiseChannel: channel,
          listensForRaise: false,
        ),
        onRaise: () {},
      );

      expect(outcome, SecondLaunchOutcome.proceed);
      expect(channel.listens, isEmpty);
    });

    test('the raise listener is on for Linux and Windows only', () {
      expect(
        DesktopSingleInstance().listensForRaise,
        Platform.isLinux || Platform.isWindows,
      );
    });

    test('still exits and says so when the raise request fails', () async {
      final channel = _FakeRaiseChannel(raiseResult: false);
      final err = _CaptureSink();

      final outcome = await handleSecondLaunch(
        guardWith(
          primitive: _FakePrimitive.alreadyRunning(),
          raiseChannel: channel,
        ),
        onRaise: () {},
        err: err,
      );

      expect(outcome, SecondLaunchOutcome.exitNow);
      expect(err.buffer.toString(), contains('could not be reached'));
    });

    test('the first instance starts listening and proceeds', () async {
      final channel = _FakeRaiseChannel();
      var raised = 0;

      final outcome = await handleSecondLaunch(
        guardWith(primitive: _FakePrimitive.acquired(), raiseChannel: channel),
        onRaise: () => raised++,
        err: _CaptureSink(),
      );

      expect(outcome, SecondLaunchOutcome.proceed);
      expect(channel.raiseRequests, isEmpty);
      expect(channel.listens, hasLength(1));
      channel.onRaise!();
      expect(raised, 1);
    });

    test('a listener failure does not block launch', () async {
      final outcome = await handleSecondLaunch(
        guardWith(
          primitive: _FakePrimitive.acquired(),
          raiseChannel: _FakeRaiseChannel(listenThrows: true),
        ),
        onRaise: () {},
        err: _CaptureSink(),
      );

      expect(outcome, SecondLaunchOutcome.proceed);
    });

    test('unavailable fails open without touching the channel', () async {
      final channel = _FakeRaiseChannel();

      final outcome = await handleSecondLaunch(
        guardWith(primitive: _FakePrimitive.throwing(), raiseChannel: channel),
        onRaise: () {},
        err: _CaptureSink(),
      );

      expect(outcome, SecondLaunchOutcome.proceed);
      expect(channel.raiseRequests, isEmpty);
      expect(channel.listens, isEmpty);
    });
  });

  group('LoopbackRaiseChannel', () {
    late LoopbackRaiseChannel server;
    late LoopbackRaiseChannel client;

    setUp(() {
      server = LoopbackRaiseChannel();
      client = LoopbackRaiseChannel();
    });

    tearDown(() async {
      await server.close();
    });

    File portFile() => File(p.join(dir.path, kSingleInstancePortFileName));

    test(
      'the first instance listens and invokes onRaise when a peer connects',
      () async {
        final raised = Completer<void>();
        final port = await server.listen(dir, raised.complete);

        expect(await portFile().readAsString(), '$port\n');
        expect(await client.requestRaise(dir), isTrue);
        await raised.future.timeout(const Duration(seconds: 5));
      },
    );

    test('ignores anything other than the raise line', () async {
      var raised = 0;
      final port = await server.listen(dir, () => raised++);

      for (final payload in ['raise-me\n', 'RAISE\n', 'hello\n', 'raise']) {
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        socket.write(payload);
        await socket.flush();
        await socket.close();
        socket.destroy();
      }
      final oversized = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      oversized.write('${'x' * 200}\nraise\n');
      await oversized.flush();
      await oversized.close();
      oversized.destroy();
      // A valid request after the junk proves the listener survived it.
      expect(await client.requestRaise(dir), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(raised, 1);
    });

    // Any local process (any user's) can connect to the loopback port, so a
    // peer must not be able to hold connections open indefinitely or open
    // without limit: each held connection is a file descriptor in the app.
    test('a peer that trickles bytes is cut off at the deadline, not kept '
        'alive by each byte', () async {
      server = LoopbackRaiseChannel(timeout: const Duration(milliseconds: 300));
      var raised = 0;
      final port = await server.listen(dir, () => raised++);
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final closed = Completer<void>();
      socket.listen(
        (_) {},
        onDone: closed.complete,
        onError: (_) {
          if (!closed.isCompleted) closed.complete();
        },
      );
      final sw = Stopwatch()..start();
      final trickle = Timer.periodic(const Duration(milliseconds: 100), (_) {
        try {
          socket.add([0x20]);
        } catch (_) {}
      });
      await closed.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => fail('connection held open by a trickling peer'),
      );
      trickle.cancel();
      socket.destroy();
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 900)));
      expect(raised, 0);
    });

    test('connections beyond the cap are dropped at once', () async {
      server = LoopbackRaiseChannel(timeout: const Duration(seconds: 5));
      final port = await server.listen(dir, () {});
      final held = [
        for (var i = 0; i < kMaxRaiseConnections; i++)
          await Socket.connect(InternetAddress.loopbackIPv4, port),
      ];
      // Let the listener accept the held ones before the extra arrives.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final extra = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final dropped = Completer<void>();
      extra.listen(
        (_) {},
        onDone: dropped.complete,
        onError: (_) {
          if (!dropped.isCompleted) dropped.complete();
        },
      );
      await dropped.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('connection over the cap was kept open'),
      );
      for (final s in [...held, extra]) {
        s.destroy();
      }
    });

    test('a stale port file does not block the new instance', () async {
      // Grab a port that nothing is listening on.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      await portFile().writeAsString('$deadPort\n');

      expect(await client.requestRaise(dir), isFalse);

      final raised = Completer<void>();
      final port = await server.listen(dir, raised.complete);
      expect(await portFile().readAsString(), '$port\n');
      expect(await client.requestRaise(dir), isTrue);
      await raised.future.timeout(const Duration(seconds: 5));
    });

    test('a missing or garbage port file reports false', () async {
      expect(await client.requestRaise(dir), isFalse);
      await portFile().writeAsString('not a port');
      expect(await client.requestRaise(dir), isFalse);
      await portFile().writeAsString('99999');
      expect(await client.requestRaise(dir), isFalse);
    });

    test('close removes the port file it wrote', () async {
      await server.listen(dir, () {});
      expect(await portFile().exists(), isTrue);

      await server.close();

      expect(await portFile().exists(), isFalse);
      expect(await client.requestRaise(dir), isFalse);
    });

    test('close leaves a port file a newer instance overwrote', () async {
      final port = await server.listen(dir, () {});
      await portFile().writeAsString('${port + 1}\n');

      await server.close();

      expect(await portFile().exists(), isTrue);
    });
  });

  // Release (AOT) builds tree-shake fields that production code never reads.
  // `_held` and the handle's `_raf` exist only to keep the locked
  // RandomAccessFile reachable; their sole reader is the test-only
  // `releaseHeld()`. Without an entry-point pragma AOT drops both, the file is
  // finalized (fd closed) about half a second after start, the OS releases the
  // advisory lock, and a second launch runs on the same database. `flutter
  // test` runs JIT, which keeps the fields, so no behavioural test here can see
  // it: this pins the annotation on each declaration instead.
  group('lock handle survives AOT tree shaking', () {
    final source = File(
      p.join('lib', 'src', 'data', 'single_instance_guard.dart'),
    ).readAsLinesSync();

    void expectEntryPoint(String declaration) {
      final line = source.indexWhere((l) => l.trim() == declaration);
      expect(line, greaterThan(0), reason: 'declaration not found');
      expect(
        source[line - 1].trim(),
        "@pragma('vm:entry-point')",
        reason: '$declaration must be kept alive in release builds',
      );
    }

    test('DesktopSingleInstance._held', () {
      expectEntryPoint('static InstanceLockHandle? _held;');
    });

    test('the lock handle\'s RandomAccessFile', () {
      expectEntryPoint('final RandomAccessFile _raf;');
    });
  });
}
