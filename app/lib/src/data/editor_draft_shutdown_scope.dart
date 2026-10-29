import 'package:flutter/widgets.dart';

import '../diagnostics/error_log.dart';

typedef EditorDraftShutdownOperation = Future<void> Function();
typedef EditorDraftShutdownPreparation =
    EditorDraftShutdownOperation Function();

Future<void> flushEditorDraftsThenClose(
  EditorDraftShutdownController controller,
  Future<void> Function() close,
) async {
  await controller.flushAll();
  await close();
}

/// Coordinates the final persistence of drafts owned by active editors.
///
/// Preparing every operation before awaiting any one of them keeps a shutdown
/// flush independent from widget disposal and makes callback ordering
/// deterministic for the shared local database.
///
/// [flushPending] is the other entry point, for the app going into the
/// background (PLAT-19): it writes any draft still waiting on its autosave
/// debounce, and the editors keep working afterwards. [flushAll] is the final
/// one, and an editor may stop autosaving once it has run.
class EditorDraftShutdownController {
  final Set<_Registration> _registrations = {};

  /// Registers an editor. [prepare] is its final flush, for [flushAll].
  /// [flushPending], when given, writes the draft its debounce is waiting to
  /// write, and must leave the editor autosaving as before; an editor without
  /// one is skipped by [flushPending].
  void Function() register(
    EditorDraftShutdownPreparation prepare, {
    EditorDraftShutdownOperation? flushPending,
  }) {
    final registration = _Registration(prepare, flushPending);
    _registrations.add(registration);
    return () {
      if (!registration.active) return;
      registration.active = false;
      _registrations.remove(registration);
    };
  }

  Future<void> flushAll() async {
    final operations = <EditorDraftShutdownOperation>[];
    for (final registration in List<_Registration>.of(_registrations)) {
      if (!registration.active) continue;
      try {
        operations.add(registration.prepare());
      } catch (error, stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'editor_draft_shutdown.prepare',
        );
      }
    }

    for (final operation in operations) {
      try {
        await operation();
      } catch (error, stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'editor_draft_shutdown.flush',
        );
      }
    }
  }

  /// Writes every draft that is waiting on its autosave debounce, without
  /// ending any editor's autosave. For the app being paused or hidden, when
  /// the OS may suspend or kill it before the debounce fires.
  Future<void> flushPending() async {
    final flushes = [
      for (final registration in List<_Registration>.of(_registrations))
        if (registration.active) ?registration.flushPending,
    ];
    for (final flush in flushes) {
      try {
        await flush();
      } catch (error, stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'editor_draft_shutdown.flush_pending',
        );
      }
    }
  }
}

class _Registration {
  _Registration(this.prepare, this.flushPending);

  final EditorDraftShutdownPreparation prepare;
  final EditorDraftShutdownOperation? flushPending;
  bool active = true;
}

class EditorDraftShutdownScope extends InheritedWidget {
  const EditorDraftShutdownScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final EditorDraftShutdownController controller;

  static EditorDraftShutdownController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<EditorDraftShutdownScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(EditorDraftShutdownScope oldWidget) =>
      controller != oldWidget.controller;
}
