/// Resolves the running platform and CPU architecture for **client-side**
/// artifact selection (ADR-002 §5). This is the one place update state touches
/// the environment, kept out of the pure model so `update_manifest.dart` stays
/// I/O-free. Nothing here is transmitted to the manifest host — selection
/// happens locally after the manifest is fetched.
library;

import 'dart:ffi' show Abi;

import 'package:flutter/foundation.dart';

import 'update_manifest.dart';

/// Maps [defaultTargetPlatform] to the manifest's [UpdatePlatform]. Fuchsia has
/// no release artifact target; it falls back to [UpdatePlatform.linux] (the
/// closest desktop) since Stage 1 only uses the selection for the — unused in
/// A11a — download link, never for gating the check.
UpdatePlatform currentUpdatePlatform() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return UpdatePlatform.android;
    case TargetPlatform.iOS:
      return UpdatePlatform.ios;
    case TargetPlatform.macOS:
      return UpdatePlatform.macos;
    case TargetPlatform.windows:
      return UpdatePlatform.windows;
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return UpdatePlatform.linux;
  }
}

/// Whether [platform] is a desktop target eligible for the assisted-download
/// flow (ADR-002 "Stage 1.5"). Desktop (linux/macos/windows) offers
/// download → verify → OS-handoff; mobile (android/ios) stays on A11a's
/// "open release page" link only.
bool isDesktopUpdatePlatform(UpdatePlatform platform) {
  switch (platform) {
    case UpdatePlatform.linux:
    case UpdatePlatform.macos:
    case UpdatePlatform.windows:
      return true;
    case UpdatePlatform.android:
    case UpdatePlatform.ios:
      return false;
  }
}

/// Derives the running [UpdateArch] from the SDK's [Abi.current]. Recognizes
/// arm64 and x64 explicitly and defaults to [UpdateArch.x64] for anything else
/// (32-bit/riscv targets the app does not ship a distinct artifact for). Note
/// macOS/Android manifests use a single `universal` artifact, so the arch only
/// discriminates on Linux/Windows in practice.
UpdateArch currentUpdateArch() {
  final abi = Abi.current().toString().toLowerCase();
  if (abi.contains('arm64')) return UpdateArch.arm64;
  if (abi.contains('x64')) return UpdateArch.x64;
  return UpdateArch.x64;
}
