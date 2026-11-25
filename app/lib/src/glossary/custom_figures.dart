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
    required this.figure,
    required this.renameNeeded,
  });

  final UserGlossaryEntry entry;

  /// The compound's definition, or null when the entry is not a compound
  /// this build can use: a kind it does not know, or a payload that no longer
  /// decodes against the taxonomy.
  final CompoundDefinition? definition;

  /// A figure of your own's definition (#1023), or null when the entry is not
  /// one this build can use.
  final UserFigureDefinition? figure;

  /// The dance form's name the entry is offered in (#1023, maintainer
  /// decision 8).
  String get form => glossaryEntryForm(entry.payload);

  /// Whether another name already claims this entry's: a shipped figure, a
  /// keyword, a dialect's move name, a shorthand, or an earlier-created entry.
  /// Of two entries sharing a name, the later-created one is flagged (#709
  /// consolidated spec, decision 6).
  final bool renameNeeded;

  /// A kind this build does not know, made by a newer version of the app. It
  /// is shown read-only, so no editor can rewrite it as another kind.
  bool get unsupported => entry.kind == null;

  /// A term (#1023): a glossary entry with no figure. Shown whenever the
  /// Glossary is, not only with Custom Figures on (maintainer decision 9).
  bool get isTerm => entry.kind == UserGlossaryEntryKind.term;

  /// A compound or figure of your own whose definition no longer decodes.
  bool get broken =>
      !unsupported &&
      switch (entry.kind) {
        UserGlossaryEntryKind.compound => definition == null,
        UserGlossaryEntryKind.customFigure => figure == null,
        _ => false,
      };

  /// The id the Glossary selects this entry by, apart from shipped ids.
  String get selectionId => customSelectionId(entry.id);
}

/// The selection id of the user entry [entryId] in the Glossary: prefixed, so
/// it can never equal a shipped move or alias id.
String customSelectionId(String entryId) => 'custom:$entryId';

/// The shipped figures whose names an entry with [payload] must not take:
/// those of the dance form it is made for, as the editor checks it, or
/// contra's for a form this build does not know.
Taxonomy glossaryEntryNameTaxonomy(Object? payload) =>
    shippedTaxonomies.forForm(glossaryEntryDanceForm(payload));

/// The dialect a shorthand is shown in: that of the form of the entry it
/// stands for ([target], the figure or combination it points at), not one
/// stored with the shorthand (#2294, maintainer decision). A target that is
/// not here, deleted or not read yet, leaves the shorthand in contra's, as it
/// has always read.
Dialect shorthandDialect(DialectsByForm dialects, UserGlossaryEntry? target) =>
    dialects.forForm(
      target == null
          ? DanceForm.contra
          : glossaryEntryDanceForm(target.payload),
    );

/// Resolves [entries] for display, in their stored order.
///
/// Each entry's name is checked against the shipped figures of its own form
/// ([glossaryEntryNameTaxonomy]), so an English figure of the user's named
/// like a shipped English figure needs renaming, as the editor says.
/// [dialects] and [shorthandTokens] are the other names a custom figure's
/// name must not take (the user's own dialects; every shorthand token), as
/// the editor checks them. [dialectsFor] adds, for one entry, the dialects
/// that entry is shown in: its own form's active dialect, whose words the
/// other forms' dialects need not share (#2294).
List<CustomGlossaryItem> resolveCustomGlossary(
  List<UserGlossaryEntry> entries, {
  Iterable<Dialect> dialects = const [],
  Iterable<Dialect> Function(Object? payload)? dialectsFor,
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
      taxonomy: glossaryEntryNameTaxonomy(entry.payload),
      dialects: [...dialects, ...?dialectsFor?.call(entry.payload)],
      shorthandTokens: shorthandTokens,
      // A dialect's own name for this figure is not a clash with it.
      exceptUserFigureId: entry.id,
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
            // Decoded with every form's figures, so an English combination
            // built from English figures decodes.
            ? decodeCompoundDefinition(entry.payload, shippedTaxonomies.anyForm)
            : null,
        figure: entry.kind == UserGlossaryEntryKind.customFigure
            ? decodeUserFigureDefinition(entry.payload)
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

/// The ids, as they came, of the shared figures in [items] whose name is
/// taken here (#1023): by one of the app's figures for the figure's own form
/// ([glossaryEntryNameTaxonomy]), a dialect name, a shorthand, one of the
/// user's entries in [live], or another figure the file brings. A figure
/// already here as it came is never listed.
///
/// [dialects] are the names every figure must not take (the user's own
/// dialects); [dialectsFor] adds, for one incoming figure, the dialects it
/// will be shown in, its own form's active dialect, as the Glossary checks it
/// ([resolveCustomGlossary], #2294), so a name the Glossary would mark Rename
/// needed is said to be taken here.
Set<String> importedFiguresWithTakenNames(
  List<UserFigureImportItem> items, {
  required List<UserGlossaryEntry> live,
  Iterable<Dialect> dialects = const [],
  Iterable<Dialect> Function(Object? payload)? dialectsFor,
  Iterable<String> shorthandTokens = const [],
}) {
  return {
    for (final item in items)
      if (item.kind != UserFigureImportKind.same &&
          glossaryNameCollisions(
            item.incoming.name,
            taxonomy: glossaryEntryNameTaxonomy(item.incoming.payload),
            dialects: [
              ...dialects,
              ...?dialectsFor?.call(item.incoming.payload),
            ],
            shorthandTokens: shorthandTokens,
            // Taking theirs replaces the figure with the same id, so its
            // name is not a clash; a copy's id belongs to another entry.
            userEntryNames: [
              for (final entry in live)
                if (item.kind != UserFigureImportKind.differs ||
                    entry.id != item.incoming.id)
                  entry.name,
              // Another figure this file brings may take the name too.
              for (final other in items)
                if (other.kind != UserFigureImportKind.same &&
                    !identical(other, item))
                  other.incoming.name,
            ],
            exceptUserFigureId: item.kind == UserFigureImportKind.copy
                ? null
                : item.incoming.id,
          ).isNotEmpty)
        item.incoming.id,
  };
}
