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
class EditorDraftShutdownController {
  final Set<_Registration> _registrations = {};

  void Function() register(EditorDraftShutdownPreparation prepare) {
    final registration = _Registration(prepare);
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
}

class _Registration {
  _Registration(this.prepare);

  final EditorDraftShutdownPreparation prepare;
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
