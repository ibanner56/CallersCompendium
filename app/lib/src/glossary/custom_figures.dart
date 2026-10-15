import 'package:compendium_core/compendium_core.dart';

/// One of the user's own glossary entries, resolved for display (#709).
///
/// Nothing here is stored: whether an entry is usable and whether it needs
/// renaming are derived on every read, because an entry can arrive by restore
/// (and later sync) in a state the editor would never have saved.
class CustomGlossaryItem {
  CustomGlossaryItem._(
    this.entry, {
    required this.definition,
    required this.renameNeeded,
  });

  final UserGlossaryEntry entry;

  /// The compound's definition, or null when the entry is not a compound
  /// this build can use: a kind it does not know, or a payload that no longer
  /// decodes against the taxonomy.
  final CompoundDefinition? definition;

  /// Whether another name already claims this entry's: a shipped figure, a
  /// keyword, a dialect's move name, a shorthand, or an earlier-created entry.
  /// Of two entries sharing a name, the later-created one is flagged (#709
  /// consolidated spec, decision 6).
  final bool renameNeeded;

  /// A kind this build cannot use: one it does not know, or one reserved for
  /// a later change (#1023's terms and figures of your own). Either was made
  /// by a newer version of the app, and is shown read-only, so the compound
  /// editor can never rewrite it as a compound.
  bool get unsupported => entry.kind != UserGlossaryEntryKind.compound;

  /// A compound whose definition no longer decodes.
  bool get broken => !unsupported && definition == null;

  /// The id the Glossary selects this entry by, apart from shipped ids.
  String get selectionId => customSelectionId(entry.id);
}

/// The selection id of the user entry [entryId] in the Glossary: prefixed, so
/// it can never equal a shipped move or alias id.
String customSelectionId(String entryId) => 'custom:$entryId';

/// Resolves [entries] for display, in their stored order.
///
/// [dialects] and [shorthandTokens] are the names a custom figure's name must
/// not take (the active dialect and the user's own dialects; every shorthand
/// token), as the editor checks them.
List<CustomGlossaryItem> resolveCustomGlossary(
  List<UserGlossaryEntry> entries, {
  required Taxonomy taxonomy,
  Iterable<Dialect> dialects = const [],
  Iterable<String> shorthandTokens = const [],
}) {
  final ordered = [...entries]
    ..sort((a, b) {
      final byCreation = a.createdAt.compareTo(b.createdAt);
      return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
    });
  final earlier = <String>{};
  final renameNeeded = <String>{};
  for (final entry in ordered) {
    final name = normalizeGlossaryName(entry.name);
    final elsewhere = glossaryNameCollisions(
      entry.name,
      taxonomy: taxonomy,
      dialects: dialects,
      shorthandTokens: shorthandTokens,
    );
    if (elsewhere.isNotEmpty || !earlier.add(name)) {
      renameNeeded.add(entry.id);
    }
  }
  return [
    for (final entry in entries)
      CustomGlossaryItem._(
        entry,
        definition: entry.kind == UserGlossaryEntryKind.compound
            ? decodeCompoundDefinition(entry.payload, taxonomy)
            : null,
        renameNeeded: renameNeeded.contains(entry.id),
      ),
  ];
}

/// Arguments that expand [definition] as its author wrote it: each parameter
/// takes the value its first bound slot holds in the template (the opposite
/// of it, for a slot bound to the opposite), or else its first allowed value.
/// Null when some parameter has no value that fits.
Map<String, Object?>? previewArguments(
  CompoundDefinition definition,
  Taxonomy taxonomy,
) {
  final args = <String, Object?>{};
  for (final param in definition.params) {
    final allowed = allowedValues(definition, param.key, taxonomy);
    Object? fromTemplate;
    for (final binding in definition.bindings) {
      if (binding.paramKey != param.key) continue;
      final template = definition.figures[binding.figureIndex];
      final slot = taxonomy.effectiveParams(template)[binding.slotKey];
      fromTemplate = binding.source == CompoundBindingSource.declared
          ? slot
          : ParamOpposites.of(param.kind, slot);
      break;
    }
    if (fromTemplate != null &&
        (allowed == null
            ? fromTemplate is String
            : allowed.contains(fromTemplate))) {
      args[param.key] = fromTemplate;
      continue;
    }
    if (allowed == null) {
      args[param.key] = '';
      continue;
    }
    if (allowed.isEmpty) return null;
    args[param.key] = allowed.first;
  }
  return args;
}
