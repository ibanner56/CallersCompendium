import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Offset, Rect, Size;

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'window_frame.dart';

/// Settings key under which the last-known desktop [WindowFrame] is persisted
/// (as JSON via [SettingsRepository]).
const String kWindowFrameKey = 'window_frame';

/// True on the desktop platforms `window_manager` supports (Windows, macOS,
/// Linux). Guards every plugin call so mobile (iOS/Android — the OS owns the
/// surface) and web (no `dart:io`) are left completely untouched.
bool get isDesktopWindowPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Coordinates an orderly desktop shutdown.
///
/// The window must remain alive while Drift sends its close request to the
/// background database isolate. Destroying it first lets Flutter tear down the
/// Dart isolate while sqlite3 native finalizers are still pending.
class WindowCloseCoordinator {
  WindowCloseCoordinator({required this.closeApp, required this.destroyWindow});

  final Future<void> Function() closeApp;
  final Future<void> Function() destroyWindow;

  Future<void>? _closeFuture;

  /// Closes application resources before force-destroying the native window.
  /// Repeated close events share the first in-flight operation.
  Future<void> handle() => _closeFuture ??= _closeAndDestroy();

  Future<void> _closeAndDestroy() async {
    try {
      await closeApp();
    } finally {
      await destroyWindow();
    }
  }
}

/// Desktop-only wiring around the `window_manager` plugin that restores the
/// last-known window size/position on startup and persists changes as the user
/// resizes/moves/maximizes the window.
///
/// This layer is intentionally thin: the flutter test harness has no real
/// window, so the testable logic (JSON (de)serialization, clamp-to-display,
/// minimum-size enforcement) lives in the pure [WindowFrame] model and is unit
/// tested there. Everything here is plugin glue guarded by
/// [isDesktopWindowPlatform].
class WindowService with WindowListener {
  WindowService(
    this._settings, {
    this.frameKey = kWindowFrameKey,
    Future<void> Function()? onClose,
  }) : _closeCoordinator = onClose == null
           ? null
           : WindowCloseCoordinator(
               closeApp: onClose,
               destroyWindow: windowManager.destroy,
             );

  final SettingsRepository _settings;
  final String frameKey;
  final WindowCloseCoordinator? _closeCoordinator;

  /// Debounce delay for persisting size/position during a drag — mirrors the
  /// editor autosave (500 ms) so we don't hammer settings mid-drag.
  static const Duration _persistDebounce = Duration(milliseconds: 500);

  Timer? _debounce;

  /// The last frame observed while the window was NOT maximized. We keep it so
  /// that when the window becomes maximized we still persist a sane restored
  /// size to fall back to on un-maximize (the plugin only reports the maximized
  /// bounds while maximized).
  WindowFrame? _lastRestoredFrame;

  /// Guards listener callbacks that fire during the initial programmatic
  /// restore so we don't immediately persist what we just applied.
  bool _restoring = false;

  /// Initializes the plugin, restores the persisted frame (clamped to the
  /// active display and a sensible minimum), shows the window, and starts
  /// listening for user-driven geometry changes. No-ops entirely off desktop.
  Future<void> initialize() async {
    if (!isDesktopWindowPlatform) return;

    await windowManager.ensureInitialized();

    final stored = await _settings.get(frameKey);
    final persisted = WindowFrame.fromJson(stored);
    final frame = await _clampToActiveDisplay(
      persisted ?? WindowFrame.defaultFrame,
    );
    _lastRestoredFrame = frame;

    // Center only when we have no known position (first launch / legacy data).
    final options = WindowOptions(
      size: Size(frame.width, frame.height),
      minimumSize: const Size(WindowFrame.minWidth, WindowFrame.minHeight),
      center: !frame.hasPosition,
    );

    _restoring = true;
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setMinimumSize(
        const Size(WindowFrame.minWidth, WindowFrame.minHeight),
      );
      if (frame.hasPosition) {
        await windowManager.setBounds(
          Rect.fromLTWH(frame.x!, frame.y!, frame.width, frame.height),
        );
      } else {
        await windowManager.setSize(Size(frame.width, frame.height));
        await windowManager.center();
      }
      if (frame.maximized) await windowManager.maximize();
      await windowManager.show();
    });
    _restoring = false;

    if (_closeCoordinator != null) {
      await windowManager.setPreventClose(true);
    }
    windowManager.addListener(this);
  }

  /// Stops listening and cancels any pending debounced write. Safe to call off
  /// desktop.
  void dispose() {
    _debounce?.cancel();
    if (isDesktopWindowPlatform) windowManager.removeListener(this);
  }

  /// Finds the display the persisted frame belongs to (the one containing its
  /// top-left, else the primary) and clamps [frame] to that display's visible
  /// bounds plus the minimum size. Falls back to the raw frame if the platform
  /// can't report displays.
  Future<WindowFrame> _clampToActiveDisplay(WindowFrame frame) async {
    try {
      final display = await _displayForFrame(frame);
      final visibleSize = display.visibleSize ?? display.size;
      final visiblePosition = display.visiblePosition ?? Offset.zero;
      return frame.clampToBounds(
        visibleWidth: visibleSize.width,
        visibleHeight: visibleSize.height,
        visibleX: visiblePosition.dx,
        visibleY: visiblePosition.dy,
      );
    } catch (_) {
      // diagnostics: silent — if display info is unavailable, still enforce the minimum size so we
      // never restore an unusably tiny window
      return frame.clampToBounds(
        visibleWidth: frame.width,
        visibleHeight: frame.height,
      );
    }
  }

  Future<Display> _displayForFrame(WindowFrame frame) async {
    final primary = await screenRetriever.getPrimaryDisplay();
    if (!frame.hasPosition) return primary;
    final displays = await screenRetriever.getAllDisplays();
    for (final display in displays) {
      final origin = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      final rect = Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
      if (rect.contains(Offset(frame.x!, frame.y!))) return display;
    }
    return primary;
  }

  // --- WindowListener: only real, user-driven changes reach these. ----------

  @override
  void onWindowResized() => _schedulePersist();

  @override
  void onWindowMoved() => _schedulePersist();

  @override
  void onWindowMaximize() {
    // Persist maximized immediately but keep the last restored size to fall
    // back to on un-maximize.
    final restored = _lastRestoredFrame ?? WindowFrame.defaultFrame;
    unawaited(_persist(restored.copyWith(maximized: true)));
  }

  @override
  void onWindowUnmaximize() {
    _debounce?.cancel();
    unawaited(_captureAndPersist());
  }

  @override
  void onWindowClose() {
    final coordinator = _closeCoordinator;
    if (coordinator != null) unawaited(coordinator.handle());
  }

  void _schedulePersist() {
    if (_restoring) return;
    _debounce?.cancel();
    _debounce = Timer(_persistDebounce, () => unawaited(_captureAndPersist()));
  }

  Future<void> _captureAndPersist() async {
    if (!isDesktopWindowPlatform || _restoring) return;
    final maximized = await windowManager.isMaximized();
    // While maximized the reported bounds are the maximized ones; keep the
    // stored restored size instead so un-maximizing later is sensible.
    if (maximized) {
      final restored = _lastRestoredFrame ?? WindowFrame.defaultFrame;
      await _persist(restored.copyWith(maximized: true));
      return;
    }
    final bounds = await windowManager.getBounds();
    final frame = WindowFrame(
      width: bounds.width,
      height: bounds.height,
      x: bounds.left,
      y: bounds.top,
    );
    _lastRestoredFrame = frame;
    await _persist(frame);
  }

  Future<void> _persist(WindowFrame frame) =>
      _settings.set(frameKey, frame.toJson());
}
