import '../model/custom_field.dart';
import '../model/enums.dart' show CustomFieldType;
import '../storage/calling_history_scope.dart' show CallingHistoryTracking;
import '../sync/sync_record_kind.dart';
import '../taxonomy/figure_param_domain.dart';
import '../taxonomy/taxonomy.dart';
import '../taxonomy/user_figure_use.dart'
    show userFigureReferenceKeys, userFigureRefKey;
import 'builder_nodes.dart';
import 'collection_panel_state.dart';
import 'collection_search_state.dart';
import 'filter.dart';
import 'saved_search.dart';

/// What a saved search refers to that no longer exists (or no longer means the
/// same), by kind.
enum MissingReferenceKind {
  tag,
  author,
  source,
  level,
  venue,
  customField,
  customFieldType,
  customFieldChoice,
  figureParam,
  userFigure,

  /// The search could not be built for another reason; never expected.
  invalid,
}

/// One thing a saved search needs that is not there. [id] is what to name in a
/// notice ("uses the tag *Bouncey*, which was deleted" — the app looks the
/// name up; for a deleted item only the id is known here).
final class MissingReference implements Comparable<MissingReference> {
  const MissingReference(this.kind, this.id);

  final MissingReferenceKind kind;
  final String id;

  @override
  int compareTo(MissingReference other) {
    final byKind = kind.index.compareTo(other.kind.index);
    return byKind != 0 ? byKind : id.compareTo(other.id);
  }

  @override
  bool operator ==(Object other) =>
      other is MissingReference && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'MissingReference(${kind.name} $id)';
}

/// The result of [resolveSavedSearch].
sealed class ResolvedSavedSearch {
  const ResolvedSavedSearch();
}

/// The saved search as a filter, against the data and settings of right now.
final class ResolvedFilter extends ResolvedSavedSearch {
  const ResolvedFilter(this.filter, this.state);

  final DanceFilter filter;

  /// The panel state the filter was built from (ids already read through the
  /// aliases), for a host that also shows it.
  final CollectionPanelState state;
}

/// The saved search cannot be evaluated as written: it names things that are
/// gone. Dropping them silently would change what it means — it broadens an
/// AND, narrows an OR, and under **None of** inverts — so a dependent feature
/// reports the saved search as needing attention rather than evaluating half
/// of it.
final class UnresolvableSavedSearch extends ResolvedSavedSearch {
  const UnresolvableSavedSearch(this.missing);

  /// Every missing reference, sorted, without duplicates. Never empty.
  final List<MissingReference> missing;
}

/// What [resolveSavedSearch] reads: the current day, the live settings that
/// are *not* part of a search, and the live data a search refers to.
class SavedSearchContext {
  const SavedSearchContext({
    required this.today,
    required this.taxonomy,
    this.callerFilter,
    this.performedOnly = false,
    this.requireEventDate = false,
    this.tracking = CallingHistoryTracking.defaults,
    this.currentProgramId,
    this.tagIds = const {},
    this.authorIds = const {},
    this.sourceIds = const {},
    this.levelIds = const {},
    this.venueIds = const {},
    this.userFigureIds = const {},
    this.customFieldDefs = const [],
    this.aliases = const {},
    this.text = const SavedSearchTextCodec(),
  });

  /// The caller's calendar day, `DateTime.utc(y, m, d)` ([calendarDayAt]).
  final DateTime today;

  final Taxonomy taxonomy;

  // Settings ▸ Calling history, in force when the search runs, not when it was
  // saved (storing a compiled CalledFilter would freeze them).
  final String? callerFilter;
  final bool performedOnly;
  final bool requireEventDate;
  final CallingHistoryTracking tracking;

  /// A program being built never counts as its own history (N1-6).
  final String? currentProgramId;

  // The live (not deleted) records a search may refer to.
  final Set<String> tagIds;
  final Set<String> authorIds;
  final Set<String> sourceIds;
  final Set<String> levelIds;
  final Set<String> venueIds;
  final Set<String> userFigureIds;
  final List<CustomFieldDef> customFieldDefs;

  /// Losing id → surviving id, by kind, as `id_aliases` holds them. A saved
  /// search that a peer edited with a merged-away id is read as the survivor.
  /// A host builds it once per run, from one read
  /// (`SyncLocalRepository.aliasMaps`), never per reference; chains are
  /// followed here.
  final Map<SyncRecordKind, Map<String, String>> aliases;

  /// How stored search text is shown: [savedSearchTextCodec] for the active
  /// dialect. A host must pass it, so the filter is built from the text the
  /// panel would hold and compiled the way the panel's is; left at the default,
  /// the stored canonical text goes to the compiler as typed.
  final SavedSearchTextCodec text;
}

/// Resolves [spec] to a [DanceFilter] against [context], or reports what it
/// refers to that is missing. Never throws.
ResolvedSavedSearch resolveSavedSearch(
  SavedSearchSpec spec,
  SavedSearchContext context,
) {
  final CollectionPanelState state;
  try {
    state = spec.toPanelState(
      map: (kind, id) => _alias(context, kind, id),
      text: context.text,
    );
  } on Object {
    return const UnresolvableSavedSearch([
      MissingReference(MissingReferenceKind.invalid, 'saved search'),
    ]);
  }
  final missing = <MissingReference>{};
  _collect(state, context, missing);
  if (missing.isNotEmpty) {
    return UnresolvableSavedSearch(missing.toList()..sort());
  }
  try {
    final filter = buildCollectionFilter(
      ftsText: state.text,
      facets: state.facets,
      defs: context.customFieldDefs,
      scope: state.scope,
      byPhrase: state.byPhrase,
      advancedRoot: state.advanced,
      callerFilter: context.callerFilter,
      performedOnly: context.performedOnly,
      requireEventDate: context.requireEventDate,
      tracking: context.tracking,
      today: context.today,
      currentProgramId: context.currentProgramId,
    );
    return ResolvedFilter(filter, state);
  } on Object {
    // Pre-validation should make this unreachable; if a leaf still refuses
    // (a constructor assertion), the search is unusable, not half-applied.
    return const UnresolvableSavedSearch([
      MissingReference(MissingReferenceKind.invalid, 'saved search'),
    ]);
  }
}

/// [id] read through [context]'s aliases: the surviving id, following chains.
/// A cycle (which sync never writes, but a restore could) leaves [id] as it
/// was, so the search reports it missing rather than looping.
String _alias(SavedSearchContext context, SyncRecordKind kind, String id) {
  final map = context.aliases[kind];
  if (map == null) return id;
  final seen = <String>{id};
  var current = id;
  while (true) {
    final next = map[current];
    if (next == null) return current;
    if (!seen.add(next)) return id;
    current = next;
  }
}

void _collect(
  CollectionPanelState state,
  SavedSearchContext c,
  Set<MissingReference> out,
) {
  final f = state.facets;
  void check(
    Iterable<String> ids,
    Set<String> live,
    MissingReferenceKind kind,
  ) {
    for (final id in ids) {
      if (!live.contains(id)) out.add(MissingReference(kind, id));
    }
  }

  check(f.tagIds, c.tagIds, MissingReferenceKind.tag);
  check(f.authorIds, c.authorIds, MissingReferenceKind.author);
  check(f.sourceIds, c.sourceIds, MissingReferenceKind.source);
  check(f.levels, c.levelIds, MissingReferenceKind.level);
  final venue = f.historyVenue?.venueId;
  if (venue != null) check([venue], c.venueIds, MissingReferenceKind.venue);

  final defs = {for (final d in c.customFieldDefs) d.id: d};
  void field(
    String id,
    CustomFieldType type, [
    Iterable<String> choices = const [],
  ]) {
    final def = defs[id];
    if (def == null) {
      out.add(MissingReference(MissingReferenceKind.customField, id));
      return;
    }
    if (def.type != type) {
      out.add(MissingReference(MissingReferenceKind.customFieldType, id));
      return;
    }
    final offered = def.choices;
    if (offered != null) {
      for (final choice in choices) {
        if (!offered.contains(choice)) {
          out.add(
            MissingReference(
              MissingReferenceKind.customFieldChoice,
              '$id=$choice',
            ),
          );
        }
      }
    }
  }

  f.choiceValues.forEach((id, values) {
    if (values.isNotEmpty) field(id, CustomFieldType.choice, values);
  });
  for (final id in f.booleanValues.keys) {
    field(id, CustomFieldType.boolean);
  }
  f.textValues.forEach((id, s) {
    if (s.isEffective) field(id, CustomFieldType.text);
  });
  f.numberValues.forEach((id, s) {
    if (s.isEffective) field(id, CustomFieldType.number);
  });

  void node(BuilderNode n) {
    switch (n) {
      case BuilderGroup():
        n.children.forEach(node);
      case BuilderTag():
        final id = n.tagId;
        if (id != null && id.isNotEmpty) {
          check([id], c.tagIds, MissingReferenceKind.tag);
        }
      case BuilderFigure():
        _figure(n, c, out);
      case BuilderThen():
        _operand(n.before, c, out);
        _operand(n.after, c, out);
    }
  }

  node(state.advanced);
}

void _operand(
  BuilderFigureNode n,
  SavedSearchContext c,
  Set<MissingReference> out,
) {
  switch (n) {
    case BuilderFigure():
      _figure(n, c, out);
    case BuilderFigureGroup():
      for (final child in n.children) {
        _operand(child, c, out);
      }
  }
}

/// A stored figure param is judged by what the Advanced panel can show and
/// clear: it must be a param the move declares (and an alias does not pin) with
/// a closed domain, holding a value in the **selectable** domain
/// ([figureParamSelectableChoices]). Anything else would narrow the search
/// with no control to clear it: a stored `unspecified`, a param a newer
/// taxonomy dropped, or a free-valued param the panel never renders. A move the
/// taxonomy does not know cannot be judged and is built as written.
void _figure(
  BuilderFigure fig,
  SavedSearchContext c,
  Set<MissingReference> out,
) {
  if (fig.isAnyFigure) return;
  final moveId = fig.move?.trim();
  final move = moveId == null ? null : c.taxonomy.resolve(moveId);
  final pinned =
      (moveId == null ? null : c.taxonomy.aliases[moveId]?.pinnedParams) ??
      const <String, Object?>{};
  for (final e in fig.params.entries) {
    final value = e.value;
    if (value == null) continue;
    if (e.key == userFigureRefKey) {
      if (value is! String || !c.userFigureIds.contains(value)) {
        out.add(MissingReference(MissingReferenceKind.userFigure, '$value'));
      }
      continue;
    }
    // The other keys of a use of a figure of your own are its arguments.
    if (userFigureReferenceKeys.contains(e.key)) continue;
    if (move == null) continue;
    final spec = move.params[e.key];
    final domain = spec == null || pinned.containsKey(e.key)
        ? null
        : figureParamChoices(spec);
    if (domain == null ||
        value is! String ||
        !figureParamSelectableChoices(domain).contains(value)) {
      out.add(
        MissingReference(
          MissingReferenceKind.figureParam,
          '${move.id}.${e.key}=$value',
        ),
      );
    }
  }
}
