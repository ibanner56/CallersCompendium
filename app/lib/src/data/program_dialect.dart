import 'package:compendium_core/compendium_core.dart';

import 'dialect_library_controller.dart';

/// Resolves a program's stored dialect [name] (`Program.dialectName`) against
/// the dialect [library], or `null` when [name] is `null` or no longer matches
/// a dialect.
///
/// A `null` result is the signal to fall back to the application dialect: a
/// program stores only a name, so a dialect that was renamed or deleted — or
/// has not synced to this device yet — silently stops resolving instead of
/// being validated or cleared on the program (issue #1554).
///
/// Names are compared after [normalizeShareableText], on both sides. The stored
/// name is NFC-normalized when the program is written, and the library's names
/// are normalized on their way to storage, but the in-memory library can hold a
/// not-yet-normalized name until it reloads, so an exact `==` (what
/// [Dialect.resolveByName] does) could miss a dialect that is really there.
/// Custom dialects are tried before the shipped presets, matching
/// [Dialect.resolveByName], so a custom dialect wins over a preset of the same
/// name.
Dialect? resolveProgramDialect(String? name, DialectLibraryController library) {
  if (name == null) return null;
  final key = normalizeShareableText(name);
  for (final dialect in [...library.customDialects, ...Dialect.presets]) {
    if (normalizeShareableText(dialect.name) == key) return dialect;
  }
  return null;
}
