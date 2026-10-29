import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// The names of the file-type filters in the native open/save dialogs.
///
/// The dialogs are opened from the data layer (`pickBackupFile`,
/// `saveDiagnosticsLog`, …), which has no `BuildContext` and is reached through
/// zero-argument test seams, so the filter names cannot be resolved where they
/// are built. The app root binds the active [AppLocalizations] here whenever the
/// language changes; until then (and in unit tests that never bind one) the
/// English strings are used.
class FileDialogLabels {
  const FileDialogLabels._();

  static AppLocalizations? _bound;

  /// The strings for the language the app is showing now.
  static AppLocalizations get current =>
      _bound ?? lookupAppLocalizations(const Locale('en'));

  /// Called from the root `MaterialApp.builder` on every build; assigning the
  /// same instance again is a no-op.
  static void bind(AppLocalizations l10n) => _bound = l10n;

  /// Forgets the bound strings so a test starts from the English fallback.
  @visibleForTesting
  static void unbind() => _bound = null;
}
