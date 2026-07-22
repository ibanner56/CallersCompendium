import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// Collects the user-content strings that the *default* (scrubbed) diagnostics
/// export must redact (issue #458): dance / program / figure titles, notes,
/// custom-field values and definitions, and tag names.
///
/// Gathered on demand from the local database at export time — export is a
/// deliberate, infrequent user action, so a full read is acceptable — and fed
/// to a [CrashRedactor]. Every source is read defensively and independently: a
/// failure to read one class must not abort the gather (and must never leave
/// content un-redacted through an exception), so each is wrapped in its own
/// guard and simply contributes nothing on failure.
///
/// Empty and very short strings are dropped: the redactor already ignores terms
/// below its minimum length, and blank titles/notes would otherwise be useless
/// (and potentially over-broad) match terms.
Future<Set<String>> collectSensitiveTerms(
  CompendiumRepositories repositories,
) async {
  final terms = <String>{};

  void add(Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.length >= 3) terms.add(text);
  }

  Future<void> guard(Future<void> Function() read) async {
    try {
      await read();
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('collectSensitiveTerms: a source failed: $error\n$stack');
      }
    }
  }

  await guard(() async {
    for (final dance in await repositories.dances.listAll(
      includeDeleted: true,
    )) {
      add(dance.title);
      add(dance.hook);
      add(dance.callingNotes);
      for (final tune in dance.tunes) {
        add(tune);
      }
      for (final figure in dance.figures) {
        add(figure.note);
      }
      for (final field in dance.customFields) {
        add(field.value);
      }
    }
  });

  await guard(() async {
    for (final program in await repositories.programs.listAll(
      includeDeleted: true,
    )) {
      add(program.title);
    }
  });

  await guard(() async {
    for (final tag in await repositories.tags.listAll()) {
      add(tag.name);
    }
  });

  await guard(() async {
    for (final def in await repositories.customFieldDefs.listAll()) {
      add(def.label);
      for (final choice in def.choices ?? const <String>[]) {
        add(choice);
      }
    }
  });

  return terms;
}
