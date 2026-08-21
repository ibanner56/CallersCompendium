import 'package:compendium_core/compendium_core.dart' show MatrixColumnConfig;
import 'package:flutter/widgets.dart';

/// Exposes the app-wide program-matrix column configuration
/// ([kProgramMatrixColumnsKey], issue #935) as a live [ValueNotifier] to the
/// widget tree.
///
/// The configuration hides / reorders / renames the matrix's built-in columns
/// and (from Phase 4/5) adds user-defined parameterized/compound columns. The
/// program editor's Matrix tab, and its PDF export, read the current
/// [MatrixColumnConfig] from here and pass it to `buildProgramMatrix` /
/// `buildProgramMatrixPdf` / `matrixColumnLabel`, so an open matrix rebuilds
/// immediately when the config changes. Follows the exact pattern of
/// `MatrixCollisionModeScope` (the #948 lesson: read the notifier's current
/// value on every dependency change, not just once at first load).
///
/// Use [ProgramMatrixColumnConfigScope.notifierOf] when you need to *change*
/// the config (e.g. Phase 3's column editor).
class ProgramMatrixColumnConfigScope
    extends InheritedNotifier<ValueNotifier<MatrixColumnConfig>> {
  const ProgramMatrixColumnConfigScope({
    super.key,
    required ValueNotifier<MatrixColumnConfig> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The active column configuration. Registers a rebuild dependency so the
  /// caller rebuilds whenever the config changes.
  ///
  /// Returns [MatrixColumnConfig.empty] (today's defaults) when there is no
  /// [ProgramMatrixColumnConfigScope] ancestor, so callers — and tests that
  /// don't wire the scope — get the unmodified matrix.
  static MatrixColumnConfig of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ProgramMatrixColumnConfigScope>();
    return scope?.notifier?.value ?? MatrixColumnConfig.empty;
  }

  /// Returns the underlying notifier so callers can change the config. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<MatrixColumnConfig> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ProgramMatrixColumnConfigScope>();
    if (scope == null) {
      throw FlutterError(
        'ProgramMatrixColumnConfigScope.notifierOf() called with a context '
        'that has no ProgramMatrixColumnConfigScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
