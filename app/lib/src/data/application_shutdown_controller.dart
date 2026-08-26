import 'dart:async';

/// Serializes requests to close the active application database.
///
/// The macOS application delegate can request shutdown while the desktop
/// window's close listener is already closing the database. Sharing the active
/// close [Future] keeps either route from racing Drift's background isolate.
class ApplicationShutdownController {
  ApplicationShutdownController(Future<void> Function() closeApp)
    : _closeApp = closeApp;

  Future<void> Function() _closeApp;
  Future<void>? _closeFuture;

  /// Closes the active application database, sharing an in-flight request.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;

    final future = Future<void>.sync(_closeApp);
    _closeFuture = future;
    future.whenComplete(() => _clearIfCurrent(future)).ignore();
    return future;
  }

  /// Replaces the close action after the database reset flow opens a new one.
  void replaceCloseApp(Future<void> Function() closeApp) {
    if (_closeFuture != null) {
      throw StateError(
        'Cannot replace the application shutdown action while closing.',
      );
    }
    _closeApp = closeApp;
  }

  void _clearIfCurrent(Future<void> future) {
    if (identical(_closeFuture, future)) _closeFuture = null;
  }
}
