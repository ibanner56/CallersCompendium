import '../model/custom_field.dart';
import '../model/enums.dart';
import '../model/formation.dart' show FormationShape;
import '../storage/calling_history_scope.dart' show CallingHistoryTracking;
import 'builder_nodes.dart';
import 'collection_facet_ids.dart';
import 'filter.dart';
import 'fts_query.dart';

/// The user's one-tap facet selections. Every facet is multi-select: within a
/// single facet the selected leaves are OR-ed ("is one of these formations"),
/// and distinct facets are AND-ed ("this form AND one of these formations"),
/// with two exceptions: [tunes] is always AND-within-facet ("has every one of
/// these tunes"), and [tagIds] follows the user's [tagsMatchAll] choice.
class FacetSelections {
  final Set<DanceForm> forms = {};
  final Set<FormationShape> formations = {};
  final Set<Progression> progressions = {};
  final Set<DanceStatus> statuses = {};
  final Set<String> levels = {};

  /// Mixed-level facet: `null` = unselected, `true`/`false` = filter to that
  /// flag. Kept separate from [levels] because "mixed" spans the ordered scale
  /// (mirrors the core [MixedLevelFilter] being distinct from [LevelFilter]).
  bool? mixedLevel;

  /// Mixer facet: `null` = unselected, `true` = show mixers only.
  /// Kept separate from formations for the same reason [mixedLevel] is
  /// separate from [levels]: mixer-ness is orthogonal to shape (issue #732,
  /// mirrors core [MixerFilter]). Only `true` is offered in the UI (tri-state
  /// null / show-mixers-only; "show non-mixers" is not offered).
  bool? mixer;

  /// Called-status selections: `true` = called, `false` = not called.
  /// Selections are OR-ed within this facet, so selecting both is unrestricted.
  final Set<bool> callStatuses = {};

  /// The venue scope of the Calling history section (N1-H2): only calls at
  /// this venue count. Null = any venue. See [scopesApply].
  VenueKey? historyVenue;

  /// What the venue chip says, kept beside [historyVenue] so the chip still
  /// reads right if the venue stops being offered (its last counted call was
  /// removed). Set and cleared with [historyVenue] by [setHistoryVenue].
  String? historyVenueLabel;

  /// The recency scope, as a preset: only calls in the last this-many calendar
  /// months count (1, 3 or 6). Null with [historySince] also null = no window.
  /// Never set together with [historySince]; use [setHistoryMonths] and
  /// [setHistorySince].
  int? historyMonths;

  /// The recency scope, as a chosen date: only calls on or after it count. A
  /// calendar date, `DateTime.utc(y, m, d)`.
  DateTime? historySince;

  /// Whether the scopes ([historyVenue], [historyMonths], [historySince]) act:
  /// only while exactly one of Called / Not called is chosen. With neither or
  /// both, no `CalledFilter` is built, so a scope would do nothing; it stays
  /// set, shown inert, and comes back when a polarity is chosen again
  /// (`docs/design/history-filters.md`, "Composition rules").
  bool get scopesApply => callStatuses.length == 1;

  /// Whether any scope is set, applying or not.
  bool get hasHistoryScope =>
      historyVenue != null || historyMonths != null || historySince != null;

  /// Sets the venue scope, or clears it when [key] is null.
  void setHistoryVenue(VenueKey? key, {String? label}) {
    historyVenue = key;
    historyVenueLabel = key == null ? null : label;
  }

  /// Sets the recency scope to the last [months] calendar months, or clears it
  /// when null.
  void setHistoryMonths(int? months) {
    historyMonths = months;
    historySince = null;
  }

  /// Sets the recency scope to calls on or after [date] (its calendar day), or
  /// clears it when null.
  void setHistorySince(DateTime? date) {
    historySince = date == null
        ? null
        : DateTime.utc(date.year, date.month, date.day);
    historyMonths = null;
  }

  /// The recency cutoff as of [today], or null when there is no window.
  /// [today] is taken as a calendar day, in whatever zone the caller means.
  DateTime? historyCutoff(DateTime today) {
    if (historySince case final since?) return since;
    if (historyMonths case final months?) {
      return calendarMonthsBefore(today, months);
    }
    return null;
  }

  /// How many scopes are set and applying, for the badges: the Calling
  /// history section's and the Filters button's.
  int get activeScopeCount => !scopesApply
      ? 0
      : (historyVenue != null ? 1 : 0) +
            (historyMonths != null || historySince != null ? 1 : 0);

  /// Minimum-rating facet: `null` = unselected, otherwise a floor on the closed
  /// `1..5` scale that emits a [RatingFilter] (`rating >= minRating`; unrated
  /// dances are excluded). Single-valued (a floor, not a multi-select set).
  int? minRating;

  final Set<String> authorIds = {};

  /// Selected tags. Change it through [setTag], which applies the
  /// [tagsMatchAll] default; reading it directly is fine.
  final Set<String> tagIds = {};

  /// Whether a dance must carry **every** selected tag (`true`, AND) or **any**
  /// of them (`false`, OR). Only meaningful, and only offered in the Filters
  /// panel, while two or more tags are selected (FIND-14).
  ///
  /// It resets to `true` whenever a second tag is added, so AND is the default
  /// each time the choice first matters; a third or later tag keeps whatever
  /// the user chose. The panel does not remember it: like every other facet
  /// selection it lasts as long as the search it belongs to, unless a saved
  /// search stores it (`SavedSearchSpec`).
  bool tagsMatchAll = true;

  /// Selects or deselects the tag [id]. Returns whether anything changed.
  ///
  /// Selecting the second tag sets [tagsMatchAll] to `true`; see there.
  bool setTag(String id, {required bool selected}) {
    if (!selected) {
      _keptTagIds.remove(id);
      return tagIds.remove(id);
    }
    if (!tagIds.add(id)) return false;
    if (tagIds.length == 2) tagsMatchAll = true;
    return true;
  }

  /// Selected tags that [retainTags] keeps even when no live dance carries
  /// them: the ones a host opened with, from a saved search or another
  /// caller's panel state ([keepSelectedTags]). A tag picked by hand is not
  /// among them.
  final Set<String> _keptTagIds = {};

  /// Marks every tag selected now as one [retainTags] keeps.
  ///
  /// A host calls this when it opens with a given panel state: a search for a
  /// tag nobody carries yet must not quietly turn into a search for anything
  /// (a dance tagged later is meant to appear), so the tag stays selected, and
  /// the Tags section shows it as a chip the user can remove.
  void keepSelectedTags() => _keptTagIds.addAll(tagIds);

  /// Drops every selected tag not in [listed], the tags the Tags facet offers
  /// (those a live dance carries), except those marked by [keepSelectedTags].
  /// Returns whether anything was dropped.
  ///
  /// A tag picked by hand whose last dance loses it would, under
  /// [tagsMatchAll], hide every dance, so the host calls this whenever its
  /// collection data changes and such a tag goes. A kept tag stays selected,
  /// and the Tags section still shows it as a chip.
  bool retainTags(Iterable<String> listed) {
    final keep = listed.toSet();
    final before = tagIds.length;
    tagIds.removeWhere((id) => !keep.contains(id) && !_keptTagIds.contains(id));
    _keptTagIds.retainAll(tagIds);
    return tagIds.length != before;
  }

  /// The Tags facet's "Untagged" chip: dances with no live tag. It never
  /// clears, or is cleared by, a tag chip, and it is always an OR alternative
  /// to the selected tags, in either [tagsMatchAll] mode: "untagged, or has
  /// every selected tag" (see [buildCollectionFilter]). AND-ing it would make
  /// any selection that includes a tag match nothing.
  ///
  /// A separate flag rather than a sentinel id in [tagIds]: a sentinel could
  /// collide with a real tag id and would leak into
  /// every consumer that treats [tagIds] as real tags (the external tag filter,
  /// tag-name lookups).
  bool untagged = false;

  /// Selected source facet: ids of cited `PublishedSource`s the user picked,
  /// each emitted as an identity-based [SourceIdFilter]. Multi-select, OR-ed
  /// within the facet — a pick-a-source chooser mirroring the Author facet
  /// (which is likewise id-based via [AuthorFilter]). Kept by id (not title)
  /// so duplicate/prefix titles or title-vs-author collisions never over-match.
  final Set<String> sourceIds = {};

  /// Tunes facet: free-text values the user entered, in entry order. Each is a
  /// case-insensitive substring tested against the dance's tune list, and a
  /// dance must match **every** one ([TunesFilter]). This is the one facet that
  /// is AND-within-facet rather than OR: a caller asking for "Dmaj" and "6/8"
  /// wants the dances that have both, not either.
  ///
  /// A list, not a set, so chips keep the order they were entered in; callers
  /// go through [addTune], which trims and refuses blanks and duplicates.
  final List<String> tunes = [];

  /// Adds [value] to [tunes] as entered (trimmed). Returns whether anything
  /// changed: a blank value, or one already present ignoring case, is refused,
  /// since a second chip for the same text could not change the result.
  bool addTune(String value) {
    final tune = value.trim();
    if (tune.isEmpty) return false;
    final key = tune.toLowerCase();
    if (tunes.any((t) => t.toLowerCase() == key)) return false;
    tunes.add(tune);
    return true;
  }

  /// Meter facet: the meters picked, as the Meter section offers them
  /// (`CollectionData.meters` in the app). OR-ed within the facet; each is a whole-value
  /// match that ignores case and accents ([MeterFilter]).
  final Set<String> meters = {};

  /// Key facet: the keys picked, as the Key section offers them, matched as
  /// [meters] are ([MusicalKeyFilter]).
  final Set<String> musicalKeys = {};

  /// Selected `choice` custom-field values, keyed by field id → chosen values
  /// (OR-within a field).
  final Map<String, Set<String>> choiceValues = {};

  /// Selected `boolean` custom-field values, keyed by field id → true/false.
  final Map<String, bool> booleanValues = {};

  /// Selected `text` custom-field filters, keyed by field id.
  /// [TextFacetState.op] is either [CustomFieldOp.contains] or
  /// [CustomFieldOp.equals]; [TextFacetState.value] is the query string.
  final Map<String, TextFacetState> textValues = {};

  /// Selected `number` custom-field filters, keyed by field id.
  /// [NumberFacetState.op] selects the operator; [NumberFacetState.lo] is
  /// always the primary value; [NumberFacetState.hi] is only used for
  /// [CustomFieldOp.between].
  final Map<String, NumberFacetState> numberValues = {};

  bool get isEmpty =>
      forms.isEmpty &&
      formations.isEmpty &&
      progressions.isEmpty &&
      statuses.isEmpty &&
      levels.isEmpty &&
      mixedLevel == null &&
      mixer == null &&
      callStatuses.isEmpty &&
      activeScopeCount == 0 &&
      minRating == null &&
      authorIds.isEmpty &&
      tagIds.isEmpty &&
      !untagged &&
      sourceIds.isEmpty &&
      tunes.isEmpty &&
      meters.isEmpty &&
      musicalKeys.isEmpty &&
      choiceValues.values.every((s) => s.isEmpty) &&
      booleanValues.isEmpty &&
      textValues.values.every((s) => !s.isEffective) &&
      numberValues.values.every((s) => !s.isEffective);

  /// How many selections are active: the number shown on the Filters button
  /// of the Collection screen and the dance picker.
  ///
  /// One per selected chip ([untagged] is a chip), one per single-valued facet
  /// ([mixedLevel], [mixer], [minRating]) and one per *effective* custom-field
  /// text/number filter — the same set [isEmpty] tests, so `activeCount == 0` exactly when
  /// [isEmpty]. [mixedLevel] and [mixer] count when non-null, not only when
  /// `true`, because [buildCollectionFilter] filters on `false` too.
  ///
  /// When adding a facet, add it to [isEmpty], [clear], [hasSelectionFor],
  /// [clearFacets], here, and to the saved-search codec (`_encodeFacets` and
  /// `_readFacets` in `saved_search.dart`), or a saved search silently leaves it
  /// out.
  int get activeCount =>
      forms.length +
      formations.length +
      progressions.length +
      statuses.length +
      levels.length +
      (mixedLevel != null ? 1 : 0) +
      (mixer != null ? 1 : 0) +
      callStatuses.length +
      activeScopeCount +
      (minRating != null ? 1 : 0) +
      authorIds.length +
      tagIds.length +
      (untagged ? 1 : 0) +
      sourceIds.length +
      tunes.length +
      meters.length +
      musicalKeys.length +
      choiceValues.values.fold<int>(0, (a, s) => a + s.length) +
      booleanValues.length +
      textValues.values.where((s) => s.isEffective).length +
      numberValues.values.where((s) => s.isEffective).length;

  void clear() {
    forms.clear();
    formations.clear();
    progressions.clear();
    statuses.clear();
    levels.clear();
    mixedLevel = null;
    mixer = null;
    callStatuses.clear();
    _clearHistoryScopes();
    minRating = null;
    authorIds.clear();
    tagIds.clear();
    _keptTagIds.clear();
    tagsMatchAll = true;
    untagged = false;
    sourceIds.clear();
    tunes.clear();
    meters.clear();
    musicalKeys.clear();
    choiceValues.clear();
    booleanValues.clear();
    textValues.clear();
    numberValues.clear();
  }

  void _clearHistoryScopes() {
    setHistoryVenue(null);
    setHistoryMonths(null);
  }

  /// Whether the filter section [id] (a `CollectionFacetIds` value or a
  /// `customFieldFacetId`) currently holds a selection. An unknown id holds
  /// none.
  bool hasSelectionFor(String id) {
    switch (id) {
      case CollectionFacetIds.form:
        return forms.isNotEmpty;
      case CollectionFacetIds.formation:
        return formations.isNotEmpty;
      case CollectionFacetIds.progression:
        return progressions.isNotEmpty;
      case CollectionFacetIds.status:
        return statuses.isNotEmpty;
      case CollectionFacetIds.level:
        return levels.isNotEmpty;
      case CollectionFacetIds.mixedLevel:
        return mixedLevel != null;
      case CollectionFacetIds.mixer:
        return mixer != null;
      case CollectionFacetIds.minRating:
        return minRating != null;
      case CollectionFacetIds.callStatus:
        return callStatuses.isNotEmpty || hasHistoryScope;
      case CollectionFacetIds.author:
        return authorIds.isNotEmpty;
      case CollectionFacetIds.tunes:
        return tunes.isNotEmpty;
      case CollectionFacetIds.meter:
        return meters.isNotEmpty;
      case CollectionFacetIds.musicalKey:
        return musicalKeys.isNotEmpty;
      case CollectionFacetIds.tags:
        return tagIds.isNotEmpty;
      case CollectionFacetIds.source:
        return sourceIds.isNotEmpty;
    }
    final defId = customFieldIdOfFacetId(id);
    if (defId == null) return false;
    return (choiceValues[defId]?.isNotEmpty ?? false) ||
        booleanValues.containsKey(defId) ||
        (textValues[defId]?.isEffective ?? false) ||
        (numberValues[defId]?.isEffective ?? false);
  }

  /// Clears the selection of every filter section named in [ids] and returns
  /// whether anything was selected, so the caller knows the results may have
  /// changed. Ids that name no section are ignored.
  bool clearFacets(Set<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (!hasSelectionFor(id)) continue;
      changed = true;
      switch (id) {
        case CollectionFacetIds.form:
          forms.clear();
        case CollectionFacetIds.formation:
          formations.clear();
        case CollectionFacetIds.progression:
          progressions.clear();
        case CollectionFacetIds.status:
          statuses.clear();
        case CollectionFacetIds.level:
          levels.clear();
        case CollectionFacetIds.mixedLevel:
          mixedLevel = null;
        case CollectionFacetIds.mixer:
          mixer = null;
        case CollectionFacetIds.minRating:
          minRating = null;
        case CollectionFacetIds.callStatus:
          callStatuses.clear();
          _clearHistoryScopes();
        case CollectionFacetIds.author:
          authorIds.clear();
        case CollectionFacetIds.tunes:
          tunes.clear();
        case CollectionFacetIds.meter:
          meters.clear();
        case CollectionFacetIds.musicalKey:
          musicalKeys.clear();
        case CollectionFacetIds.tags:
          tagIds.clear();
          _keptTagIds.clear();
          tagsMatchAll = true;
        case CollectionFacetIds.source:
          sourceIds.clear();
        default:
          final defId = customFieldIdOfFacetId(id);
          if (defId != null) {
            choiceValues.remove(defId);
            booleanValues.remove(defId);
            textValues.remove(defId);
            numberValues.remove(defId);
          }
      }
    }
    return changed;
  }
}

/// The calendar day [months] calendar months before [today]'s day, as the
/// `DateTime.utc(y, m, d)` a stored event date and `CalledFilter.since` use.
///
/// A day the earlier month lacks clamps to that month's last day, so one month
/// before 31 March is 28 (or 29) February, never 3 March.
DateTime calendarMonthsBefore(DateTime today, int months) {
  final index = today.year * 12 + (today.month - 1) - months;
  final year = index ~/ 12;
  final month = index % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, today.day > lastDay ? lastDay : today.day);
}

/// The user's "By phrase" selections — a Caller's Box-style per-phrase figure
/// search. For each canonical section label (the standard 4 phrases A1/A2/B1/B2,
/// but keyed generically so any `PhraseStructure` works) the caller lists moves
/// that MUST occur in that phrase ([match]) and moves that must NOT ([exclude]).
///
/// Semantics (folded in [buildCollectionFilter]):
/// - within one phrase, every [match] move must be present (AND);
/// - within one phrase, no [exclude] move may be present (each negated);
/// - across phrases, all constraints AND together;
/// - an empty phrase imposes no constraint.
///
/// Moves are stored as canonical move ids (the same ids the Advanced builder's
/// "has figure" rows use), so they compile straight to [FigureLeaf]s.
class ByPhraseSelections {
  /// Section label → moves that MUST occur in that phrase.
  final Map<String, List<String>> match = {};

  /// Section label → moves that must NOT occur in that phrase.
  final Map<String, List<String>> exclude = {};

  bool get isEmpty =>
      match.values.every((m) => m.isEmpty) &&
      exclude.values.every((m) => m.isEmpty);

  void clear() {
    match.clear();
    exclude.clear();
  }
}

/// Immutable state for a text custom-field facet filter.
class TextFacetState {
  const TextFacetState({required this.op, required this.value});

  /// Either [CustomFieldOp.contains] or [CustomFieldOp.equals].
  final CustomFieldOp op;

  /// The text to match against.
  final String value;

  /// True when this state would actually produce a [CustomFieldFilter] branch
  /// in [buildCollectionFilter] (i.e. the value is non-empty after trimming).
  bool get isEffective => value.trim().isNotEmpty;
}

/// Immutable state for a number custom-field facet filter.
class NumberFacetState {
  const NumberFacetState({required this.op, required this.lo, this.hi});

  /// One of [CustomFieldOp.eq], [CustomFieldOp.lt], [CustomFieldOp.gt], or
  /// [CustomFieldOp.between].
  final CustomFieldOp op;

  /// The primary operand (always required).
  final num lo;

  /// The upper bound for [CustomFieldOp.between] (required only for that op).
  final num? hi;

  /// True when this state would actually produce a [CustomFieldFilter] branch
  /// in [buildCollectionFilter] (i.e. non-between ops are always effective;
  /// between is only effective once [hi] is also set).
  bool get isEffective => op != CustomFieldOp.between || hi != null;
}

/// OR-combines [leaves] into a single [DanceFilter]: `null` for none, the leaf
/// itself for one, an [OrFilter] for many. Used to fold a multi-select facet
/// down to one branch of the top-level `AND`.
DanceFilter? orGroup(List<DanceFilter> leaves) => switch (leaves.length) {
  0 => null,
  1 => leaves.single,
  _ => OrFilter(leaves),
};

/// Builds the composed [DanceFilter] for a Collection search: the full-text
/// query, the facet selections, and the (optional) Advanced tree, AND-ed into
/// one flat tree. Returns `AndFilter([])` (match-all) when nothing is set.
///
/// [defs] supplies the custom-field definitions the facet selections refer to
/// (needed to build the typed [CustomFieldFilter] leaves).
///
/// [currentProgramId] is passed to the [CalledFilter], so a program being built
/// never counts as its own history (N1-6). Collection leaves it null; the
/// program builder's add-dance picker passes the program it is editing
/// (#2343).
DanceFilter buildCollectionFilter({
  required String ftsText,
  required FacetSelections facets,
  required List<CustomFieldDef> defs,
  FullTextScope scope = FullTextScope.omni,
  ByPhraseSelections? byPhrase,
  BuilderGroup? advancedRoot,
  String? callerFilter,
  bool performedOnly = false,
  bool requireEventDate = false,
  CallingHistoryTracking tracking = CallingHistoryTracking.defaults,
  DateTime? today,
  String? currentProgramId,
}) {
  final branches = <DanceFilter>[];

  final text = ftsText.trim();
  if (text.isNotEmpty) {
    branches.add(FullTextFilter(text, scope: scope));
  }

  void addOr(List<DanceFilter> leaves) {
    final g = orGroup(leaves);
    if (g != null) branches.add(g);
  }

  addOr([for (final f in facets.forms) FormFilter(f)]);
  addOr([for (final s in facets.formations) FormationFilter(s)]);
  addOr([for (final p in facets.progressions) ProgressionFilter(p)]);
  addOr([for (final s in facets.statuses) StatusFilter(s)]);
  addOr([for (final id in facets.levels) LevelFilter(id)]);
  if (facets.mixedLevel != null) {
    branches.add(MixedLevelFilter(facets.mixedLevel!));
  }
  if (facets.mixer != null) {
    branches.add(MixerFilter(facets.mixer!));
  }
  if (facets.scopesApply) {
    addOr([
      CalledFilter(
        called: facets.callStatuses.single,
        callerFilter: callerFilter,
        performedOnly: performedOnly,
        requireEventDate: requireEventDate,
        tracking: tracking,
        venue: facets.historyVenue,
        since: facets.historyCutoff(today ?? DateTime.now()),
        currentProgramId: currentProgramId,
      ),
    ]);
  }
  if (facets.minRating != null) {
    branches.add(RatingFilter(facets.minRating!));
  }
  addOr([for (final id in facets.authorIds) AuthorFilter(id)]);
  final tagLeaves = [for (final id in facets.tagIds) TagFilter(id)];
  final allTags = facets.tagsMatchAll && tagLeaves.length > 1;
  if (allTags && !facets.untagged) {
    // Each tag is already a top-level AND operand, as for Tunes below.
    branches.addAll(tagLeaves);
  } else {
    addOr([
      if (allTags) AndFilter(tagLeaves) else ...tagLeaves,
      if (facets.untagged) const UntaggedFilter(),
    ]);
  }
  addOr([for (final id in facets.sourceIds) SourceIdFilter(id)]);
  // AND within the facet, like Tags under All tags above: one branch per
  // entered value, each already a top-level AND operand, so no OR/AND group is
  // built.
  for (final tune in facets.tunes) {
    branches.add(TunesFilter(tune));
  }
  addOr([for (final m in facets.meters) MeterFilter(m)]);
  addOr([for (final k in facets.musicalKeys) MusicalKeyFilter(k)]);

  final defsById = {for (final d in defs) d.id: d};
  facets.choiceValues.forEach((fieldId, values) {
    final def = defsById[fieldId];
    if (def == null || values.isEmpty) return;
    addOr([
      for (final v in values) CustomFieldFilter(def, CustomFieldOp.is_, v),
    ]);
  });
  facets.booleanValues.forEach((fieldId, value) {
    final def = defsById[fieldId];
    if (def == null) return;
    branches.add(CustomFieldFilter(def, CustomFieldOp.is_, value));
  });
  facets.textValues.forEach((fieldId, state) {
    final def = defsById[fieldId];
    if (def == null || !state.isEffective) return;
    branches.add(CustomFieldFilter(def, state.op, state.value.trim()));
  });
  facets.numberValues.forEach((fieldId, state) {
    final def = defsById[fieldId];
    if (def == null || !state.isEffective) return;
    if (state.op == CustomFieldOp.between) {
      branches.add(
        CustomFieldFilter(def, CustomFieldOp.between, [state.lo, state.hi!]),
      );
    } else {
      branches.add(CustomFieldFilter(def, state.op, state.lo));
    }
  });

  final advanced = advancedRoot?.toFilter();
  if (advanced != null) branches.add(advanced);

  // By-phrase constraints (Caller's Box style): each "match" move must occur in
  // its phrase (a positive sectioned FigureFilter); each "do not match" move
  // must be absent (the same sectioned leaf, negated). Empty phrases add
  // nothing. All fold into the top-level AND alongside every other facet.
  if (byPhrase != null) {
    void addFigure(String section, String move, {required bool negate}) {
      final id = move.trim();
      if (id.isEmpty) return;
      final DanceFilter leaf = FigureFilter(FigureLeaf(id, section: section));
      branches.add(negate ? NotFilter(leaf) : leaf);
    }

    byPhrase.match.forEach((section, moves) {
      for (final move in moves) {
        addFigure(section, move, negate: false);
      }
    });
    byPhrase.exclude.forEach((section, moves) {
      for (final move in moves) {
        addFigure(section, move, negate: true);
      }
    });
  }

  if (branches.isEmpty) return const AndFilter([]);
  if (branches.length == 1) {
    final only = branches.single;
    // A lone OR/AND branch is already a valid top-level filter; a lone leaf is
    // too. Return it directly rather than wrapping in a redundant AND.
    return only;
  }
  return AndFilter(branches);
}

/// Whether a search made of [ftsText] + [facets] + [advancedRoot] is a **bare**
/// full-text search — the only case where FTS `relevance` sort is meaningful
/// (`docs/design/search.md` decision 6).
bool isBareFullText({
  required String ftsText,
  required FacetSelections facets,
  FullTextScope scope = FullTextScope.omni,
  ByPhraseSelections? byPhrase,
  BuilderGroup? advancedRoot,
}) =>
    ftsText.trim().isNotEmpty &&
    scope == FullTextScope.omni &&
    ftsQueryScalarLength(ftsText) <= 2 &&
    facets.isEmpty &&
    (byPhrase == null || byPhrase.isEmpty) &&
    (advancedRoot == null || advancedRoot.toFilter() == null);
