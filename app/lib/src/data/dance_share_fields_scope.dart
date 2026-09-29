import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Propagates the user's chosen set of [DanceShareField]s — which non-figures
/// `Dance` fields appear when a program/dance is shared, copied, or exported
/// to PDF (issue #1434) — to descendants as a live [ValueNotifier].
///
/// Same shape as [CollectionTileFieldsScope] (issue #767): placed at the root
/// of the widget tree so the settings screen — a sibling of the export call
/// sites in the navigation tree — can write to the notifier via [notifierOf].
///
/// **Current state (issue #1434, this PR):** the scope is mounted at the app
/// root and the Settings screen reads/writes it, but **no export call site
/// reads it yet** — `ProgramExportMenu`, `DanceExportMenu`, and the
/// dance-detail screen's export actions are wired to read
/// [DanceShareFieldsScope.of] and pass the result into the core renderers in
/// follow-up PRs. Toggling the Settings checkboxes this PR adds has no
/// visible effect on any export until that wiring lands.
///
/// **Reading the value:** call [DanceShareFieldsScope.of] inside `build`. It
/// returns [DanceShareField.allExceptTunes] when no ancestor is present,
/// preserving pre-feature rendering for any call site (or test) that doesn't
/// wire the scope.
///
/// **Writing the value:** call [DanceShareFieldsScope.notifierOf] from a
/// settings widget to update and persist the preference.
class DanceShareFieldsScope
    extends InheritedNotifier<ValueNotifier<Set<DanceShareField>>> {
  const DanceShareFieldsScope({
    super.key,
    required ValueNotifier<Set<DanceShareField>> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The set of fields currently selected. Registers a rebuild dependency so
  /// the caller rebuilds whenever the notifier changes.
  ///
  /// Returns [DanceShareField.allExceptTunes] (every field this feature's
  /// renderers emitted unconditionally before the picker existed, minus
  /// tunes) when there is no [DanceShareFieldsScope] ancestor, so tests and
  /// call sites without the scope wired behave identically to the
  /// pre-feature state.
  static Set<DanceShareField> of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DanceShareFieldsScope>();
    return scope?.notifier?.value ?? DanceShareField.allExceptTunes;
  }

  /// Returns the underlying notifier for write-from-settings use. Does NOT
  /// register a rebuild dependency.
  ///
  /// Throws if no [DanceShareFieldsScope] ancestor exists.
  static ValueNotifier<Set<DanceShareField>> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<DanceShareFieldsScope>();
    if (scope == null) {
      throw FlutterError(
        'DanceShareFieldsScope.notifierOf() called with a context that '
        'has no DanceShareFieldsScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// Decodes a raw settings value (from `kProgramDanceShareFieldsKey`) into a
  /// [Set<DanceShareField>] for use as the initial notifier value.
  ///
  /// Three cases, mirroring [CollectionTileFieldsScope.decodeStored]:
  ///
  /// - [stored] is not a `List` (key absent or corrupt) →
  ///   [DanceShareField.allExceptTunes]: the preference has never been saved,
  ///   so default to the pre-feature field set.
  /// - [stored] is an empty `List` → empty set: the user deliberately turned
  ///   off every field and that choice must be honoured on restart.
  /// - [stored] is a non-empty `List` → decode recognised names; if every
  ///   name is unrecognised (e.g. stored on a future build, opened on an
  ///   older one) fall back to [DanceShareField.allExceptTunes] so unknown
  ///   fields don't silently disappear.
  static Set<DanceShareField> decodeStored(dynamic stored) {
    if (stored is! List) return DanceShareField.allExceptTunes;
    if (stored.isEmpty) return const {};
    final decoded = stored
        .whereType<String>()
        .map(DanceShareField.fromJson)
        .whereType<DanceShareField>()
        .toSet();
    return decoded.isEmpty ? DanceShareField.allExceptTunes : decoded;
  }
}
