import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Reports the bytes an unprivileged process may still write on the
/// filesystem holding a directory, or null when it cannot tell.
typedef AthenaeumFreeSpaceProbe = int? Function(String directory);

/// The bytes available to an unprivileged writer on the filesystem holding
/// [directory]: `f_bavail × f_frsize` from `statvfs(3)`, the figure `df`
/// reports as *Available*. Null when it cannot be read.
///
/// Read through `dart:ffi` from the C library already loaded into the process,
/// because `dart:io` exposes no free-space call. The alternatives were worse
/// for a check that runs on every write request: running `df` costs a process
/// spawn each time (or a cache that can be stale across exactly the write that
/// crosses the floor) and parses text whose layout varies between `df`
/// implementations; and `/proc` reports memory and mounts, not free space on a
/// filesystem. `statvfs` is one system call, and in the reference deployment it
/// sees what matters: the data directory is a bind mount of a host directory
/// (`docs/dev/athenaeum-operations.md`), and `statvfs` on a bind mount reports
/// the host filesystem behind it.
///
/// Only 64-bit Linux is read, the platform the reference image runs on. There,
/// glibc and musl share one `struct statvfs` layout whose leading fields are
/// all 8 bytes (`f_bsize`, `f_frsize`, `f_blocks`, `f_bfree`, `f_bavail`,
/// …), so `f_frsize` is at offset 8 and `f_bavail` at offset 32. Other
/// platforms lay the struct out differently (macOS narrows the block counts to
/// 32 bits), so rather than guess, this returns null there and the floor is not
/// enforced; the server's `main` (`bin/athenaeum.dart`) says so on stderr at
/// startup.
int? statvfsAvailableBytes(String directory) {
  if (!Platform.isLinux || sizeOf<IntPtr>() != 8) return null;
  final statvfs = _statvfs;
  if (statvfs == null) return null;
  // Larger than the 112-byte struct, so a C library that grew it cannot write
  // past the buffer.
  final buffer = calloc<Uint8>(_statvfsBufferBytes);
  final path = directory.toNativeUtf8();
  try {
    if (statvfs(path, buffer) != 0) return null;
    final fields = buffer.cast<Uint64>();
    final fragmentSize = fields[1];
    final availableBlocks = fields[4];
    if (fragmentSize <= 0 || availableBlocks < 0) return null;
    return fragmentSize * availableBlocks;
  } finally {
    malloc.free(path);
    calloc.free(buffer);
  }
}

const int _statvfsBufferBytes = 256;

typedef _StatvfsNative = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _StatvfsDart = int Function(Pointer<Utf8>, Pointer<Uint8>);

final _StatvfsDart? _statvfs = () {
  try {
    return DynamicLibrary.process()
        .lookupFunction<_StatvfsNative, _StatvfsDart>('statvfs');
  } on ArgumentError {
    return null;
  }
}();
