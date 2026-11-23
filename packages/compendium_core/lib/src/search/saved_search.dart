import 'dart:convert';

import '../model/enums.dart';
import '../model/formation.dart' show FormationShape;
import '../sync/sync_record_kind.dart';
import 'builder_nodes.dart';
import 'collection_panel_state.dart';
import 'collection_search_state.dart';
import 'collection_sort.dart';
import 'filter.dart';
import 'search_clock.dart';
import 'search_sort.dart';

/// The format version this build writes and reads.
const int savedSearchFormatVersion = 1;

/// Hard limits on a stored saved search, far under the sync server's own
/// (JSON depth 32, 1 MiB a blob), so a hostile or buggy value is refused here
/// rather than there. A value over any of them is *unreadable*, never
/// partially applied.
const int savedSearchMaxDepth = 8;
const int savedSearchMaxNodes = 200;
const int savedSearchMaxString = 500;
const int savedSearchMaxItems = 200;
const int savedSearchMaxBytes = 64 * 1024;
const int savedSearchMaxNameLength = 100;

/// Maps a reference's id to the id it should be read as, for a given kind of
/// record: the way a merge's losing id is read as the survivor's.
typedef SavedSearchIdMapper = String Function(SyncRecordKind kind, String id);

String _keepId(SyncRecordKind kind, String id) => id;

/// What reading or building a saved search produced: a value, or why it
/// cannot be one. Never thrown: a stored value is outside input.
final class SavedSearchDecoded<T> {
  const SavedSearchDecoded.ok(T this.value) : problem = null;
  const SavedSearchDecoded.bad(String this.problem) : value = null;

  final T? value;

  /// Why the value cannot be read, for a notice ("needs attention").
  final String? problem;

  bool get isOk => problem == null;
}

/// Turns the search text the user typed into the text that is stored, and the
/// stored text back into what the search bar shows (`docs/design/search.md`,
/// "Dialect canonicalization of input"). The default keeps text as given.
///
/// A saved search stores its text canonicalized against the dialect it was
/// typed in, so "larks chain" means the same dances after a switch to a
/// dialect that calls the roles something else.
class SavedSearchTextCodec {
  const SavedSearchTextCodec({this.canonicalize = _same, this.display = _same});

  final String Function(String typed) canonicalize;
  final String Function(String stored) display;

  static String _same(String text) => text;
}

/// A saved search's content: the persisted form of a [CollectionPanelState],
/// held as a validated, deeply immutable JSON value.
///
/// It stores the panel state, **not** a compiled filter: a compiled filter
/// would freeze the computed recency cutoff and the settings-derived calling
/// history fields (#2325). It stores a history
/// window as a *distance* in calendar months, never as a date.
final class SavedSearchSpec {
  SavedSearchSpec._(this._json);

  final Map<String, Object?> _json;

  /// The JSON form, deeply unmodifiable.
  Map<String, Object?> toJson() => _json;

  /// Builds the spec for [state] as of [today] (a calendar day). A chosen
  /// date window is saved as the whole months back it is from [today]
  /// ([monthsBackFromDate]); a state that exceeds the format's limits is
  /// rejected, not truncated.
  static SavedSearchDecoded<SavedSearchSpec> fromPanelState(
    CollectionPanelState state, {
    required DateTime today,
    SavedSearchTextCodec text = const SavedSearchTextCodec(),
  }) {
    final Map<String, Object?> json;
    try {
      json = _encode(state, today, text);
    } on Object catch (e) {
      return SavedSearchDecoded.bad('cannot be saved: $e');
    }
    return decode(json);
  }

  /// Reads [json], strictly. An unknown version, key, type or enum name, or a
  /// value over a limit, makes it unreadable. Never throws.
  static SavedSearchDecoded<SavedSearchSpec> decode(Object? json) {
    try {
      if (json is! Map) return const SavedSearchDecoded.bad('not an object');
      final frozen = _freeze(json) as Map<String, Object?>;
      if (utf8.encode(jsonEncode(frozen)).length > savedSearchMaxBytes) {
        return const SavedSearchDecoded.bad('too large');
      }
      // Reading is the validation: hydrating once proves every field.
      _hydrate(frozen, _keepId, const SavedSearchTextCodec());
      return SavedSearchDecoded.ok(SavedSearchSpec._(frozen));
    } on _Invalid catch (e) {
      return SavedSearchDecoded.bad(e.reason);
    } on Object catch (e) {
      // Anything unforeseen (a cyclic or exotic value) is still just unreadable.
      return SavedSearchDecoded.bad('unreadable: ${e.runtimeType}');
    }
  }

  /// The live panel state this spec describes, with every reference read
  /// through [map] (a merge's alias) and the text shown through [text]. Always
  /// a fresh state, with fresh builder ids.
  CollectionPanelState toPanelState({
    SavedSearchIdMapper map = _keepId,
    SavedSearchTextCodec text = const SavedSearchTextCodec(),
  }) => _hydrate(_json, map, text);
}

/// One saved search: a stable [id] (the key suffix), a [name] the user sees,
/// and its content.
final class SavedSearch {
  const SavedSearch({required this.id, required this.name, required this.spec});

  final String id;
  final String name;
  final SavedSearchSpec spec;

  /// The value to store for this search (one value per saved search).
  Map<String, Object?> toJson() => {...spec.toJson(), 'name': name};

  /// Reads the value stored for [id]. Never throws.
  static SavedSearchDecoded<SavedSearch> decode(String id, Object? json) {
    if (json is! Map) return const SavedSearchDecoded.bad('not an object');
    final name = json['name'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > savedSearchMaxNameLength) {
      return const SavedSearchDecoded.bad('name: missing or invalid');
    }
    final rest = {
      for (final e in json.entries)
        if (e.key != 'name') e.key: e.value,
    };
    final spec = SavedSearchSpec.decode(rest);
    final value = spec.value;
    if (value == null) return SavedSearchDecoded.bad(spec.problem!);
    return SavedSearchDecoded.ok(SavedSearch(id: id, name: name, spec: value));
  }
}

/// Whether the compiler reads the search text through the active dialect for
/// [scope]. **All fields** and **Figures** do (canonical form); **Title** and
/// **Author** match only the typed word, so a dialect never changes what they
/// find, and canonicalizing their text would only change which titles and
/// names match.
bool _readsDialect(FullTextScope scope) =>
    scope == FullTextScope.omni || scope == FullTextScope.figure;

// ---------------------------------------------------------------------------
// Reading (also the validation).
// ---------------------------------------------------------------------------

final class _Invalid implements Exception {
  _Invalid(this.reason);
  final String reason;
}

Never _bad(String at, String why) => throw _Invalid('$at: $why');

Object? _freeze(Object? v) {
  if (v is Map) {
    final frozen = <String, Object?>{};
    for (final e in v.entries) {
      final key = e.key;
      if (key is! String) throw _Invalid('object key is not a string');
      frozen[key] = _freeze(e.value);
    }
    return Map<String, Object?>.unmodifiable(frozen);
  }
  if (v is List) return List<Object?>.unmodifiable(v.map(_freeze));
  return v;
}

Map<String, Object?> _obj(Object? v, String at, Set<String> keys) {
  if (v is! Map) _bad(at, 'not an object');
  final m = v.cast<String, Object?>();
  for (final k in m.keys) {
    if (!keys.contains(k)) _bad(at, 'unknown key "$k"');
  }
  return m;
}

String _str(Object? v, String at, {bool allowEmpty = false}) {
  if (v is! String) _bad(at, 'not a string');
  if (v.length > savedSearchMaxString) _bad(at, 'too long');
  if (!allowEmpty && v.trim().isEmpty) _bad(at, 'empty');
  return v;
}

bool _bool(Object? v, String at) {
  if (v is! bool) _bad(at, 'not a boolean');
  return v;
}

int _int(Object? v, String at, {required int min, required int max}) {
  if (v is! int || v < min || v > max) _bad(at, 'not an integer $min..$max');
  return v;
}

num _num(Object? v, String at) {
  if (v is! num || !v.isFinite) _bad(at, 'not a finite number');
  return v;
}

List<Object?> _list(Object? v, String at) {
  if (v is! List) _bad(at, 'not a list');
  if (v.length > savedSearchMaxItems) _bad(at, 'too many entries');
  return v;
}

T _enum<T extends Enum>(Object? v, List<T> values, String at) {
  if (v is String) {
    for (final e in values) {
      if (e.name == v) return e;
    }
  }
  return _bad(at, 'unknown value');
}

class _Budget {
  int nodes = 0;
  void spend(String at) {
    if (++nodes > savedSearchMaxNodes) _bad(at, 'too many rows');
  }
}

const _topKeys = {
  'v',
  'text',
  'scope',
  'sort',
  'sortDirection',
  'facets',
  'byPhrase',
  'advanced',
};

CollectionPanelState _hydrate(
  Map<String, Object?> json,
  SavedSearchIdMapper map,
  SavedSearchTextCodec text,
) {
  final m = _obj(json, 'saved search', _topKeys);
  final v = m['v'];
  if (v is! int) _bad('v', 'missing version');
  if (v != savedSearchFormatVersion) {
    _bad('v', 'version $v is not readable by this build');
  }
  final sort = m.containsKey('sort')
      ? _enum(m['sort'], CollectionSort.values, 'sort')
      : CollectionSort.title;
  final scope = m.containsKey('scope')
      ? _enum(m['scope'], FullTextScope.values, 'scope')
      : FullTextScope.omni;
  final stored = m.containsKey('text')
      ? _str(m['text'], 'text', allowEmpty: true)
      : '';
  final state = CollectionPanelState(
    text: _readsDialect(scope) ? text.display(stored) : stored,
    scope: scope,
    sort: sort,
    sortDirection: m.containsKey('sortDirection')
        ? _enum(m['sortDirection'], SortDirection.values, 'sortDirection')
        : sort.searchSort.defaultDirection,
  );
  if (m.containsKey('facets')) _readFacets(m['facets'], state.facets, map);
  if (m.containsKey('byPhrase')) _readByPhrase(m['byPhrase'], state.byPhrase);
  if (m.containsKey('advanced')) {
    final advanced = m['advanced'];
    final budget = _Budget();
    final root = _readNode(advanced, 1, budget, map, 'advanced');
    if (root is! BuilderGroup) _bad('advanced', 'root is not a group');
    state.advanced
      ..kind = root.kind
      ..children.addAll(root.children);
  }
  return state;
}

const _facetKeys = {
  'forms',
  'formations',
  'progressions',
  'statuses',
  'levels',
  'mixedLevel',
  'mixer',
  'callStatuses',
  'historyVenue',
  'historyMonths',
  'minRating',
  'authorIds',
  'tagIds',
  'tagsMatchAll',
  'untagged',
  'sourceIds',
  'tunes',
  'meters',
  'musicalKeys',
  'choiceValues',
  'booleanValues',
  'textValues',
  'numberValues',
};

void _readFacets(Object? v, FacetSelections f, SavedSearchIdMapper map) {
  final m = _obj(v, 'facets', _facetKeys);
  void each(String key, void Function(Object? item, String at) add) {
    if (!m.containsKey(key)) return;
    final list = _list(m[key], 'facets.$key');
    for (var i = 0; i < list.length; i++) {
      add(list[i], 'facets.$key[$i]');
    }
  }

  each('forms', (x, at) => f.forms.add(_enum(x, DanceForm.values, at)));
  each(
    'formations',
    (x, at) => f.formations.add(_enum(x, FormationShape.values, at)),
  );
  each(
    'progressions',
    (x, at) => f.progressions.add(_enum(x, Progression.values, at)),
  );
  each('statuses', (x, at) => f.statuses.add(_enum(x, DanceStatus.values, at)));
  each(
    'levels',
    (x, at) => f.levels.add(map(SyncRecordKind.difficultyLevel, _str(x, at))),
  );
  if (m.containsKey('mixedLevel')) {
    f.mixedLevel = _bool(m['mixedLevel'], 'facets.mixedLevel');
  }
  if (m.containsKey('mixer')) f.mixer = _bool(m['mixer'], 'facets.mixer');
  each('callStatuses', (x, at) => f.callStatuses.add(_bool(x, at)));
  if (m.containsKey('historyVenue')) {
    final key = VenueKey.fromStorageKey(
      _str(m['historyVenue'], 'facets.historyVenue'),
    );
    if (key == null) _bad('facets.historyVenue', 'not a venue key');
    final id = key.venueId;
    f.setHistoryVenue(
      id == null ? key : VenueKey.record(map(SyncRecordKind.venue, id)),
    );
  }
  if (m.containsKey('historyMonths')) {
    f.setHistoryMonths(
      _int(m['historyMonths'], 'facets.historyMonths', min: 1, max: 1200),
    );
  }
  if (m.containsKey('minRating')) {
    f.minRating = _int(m['minRating'], 'facets.minRating', min: 1, max: 5);
  }
  each(
    'authorIds',
    (x, at) => f.authorIds.add(map(SyncRecordKind.choreographer, _str(x, at))),
  );
  each('tagIds', (x, at) => f.tagIds.add(map(SyncRecordKind.tag, _str(x, at))));
  if (m.containsKey('tagsMatchAll')) {
    f.tagsMatchAll = _bool(m['tagsMatchAll'], 'facets.tagsMatchAll');
  }
  if (m.containsKey('untagged')) {
    f.untagged = _bool(m['untagged'], 'facets.untagged');
  }
  each(
    'sourceIds',
    (x, at) =>
        f.sourceIds.add(map(SyncRecordKind.publishedSource, _str(x, at))),
  );
  each('tunes', (x, at) => f.addTune(_str(x, at)));
  each('meters', (x, at) => f.meters.add(_str(x, at)));
  each('musicalKeys', (x, at) => f.musicalKeys.add(_str(x, at)));

  Map<String, Object?> fields(String key) {
    final obj = m[key];
    if (obj is! Map) _bad('facets.$key', 'not an object');
    if (obj.length > savedSearchMaxItems) {
      _bad('facets.$key', 'too many fields');
    }
    return obj.cast<String, Object?>();
  }

  if (m.containsKey('choiceValues')) {
    for (final e in fields('choiceValues').entries) {
      final at = 'facets.choiceValues.${e.key}';
      final values = {for (final x in _list(e.value, at)) _str(x, at)};
      // Two ids read as one (a merged-away field) keep both fields' choices.
      f.choiceValues
          .putIfAbsent(
            map(SyncRecordKind.customFieldDef, _str(e.key, at)),
            () => <String>{},
          )
          .addAll(values);
    }
  }
  if (m.containsKey('booleanValues')) {
    for (final e in fields('booleanValues').entries) {
      final at = 'facets.booleanValues.${e.key}';
      f.booleanValues[map(SyncRecordKind.customFieldDef, _str(e.key, at))] =
          _bool(e.value, at);
    }
  }
  if (m.containsKey('textValues')) {
    for (final e in fields('textValues').entries) {
      final at = 'facets.textValues.${e.key}';
      final o = _obj(e.value, at, {'op', 'value'});
      final op = _enum(o['op'], [
        CustomFieldOp.contains,
        CustomFieldOp.equals,
      ], at);
      f.textValues[map(SyncRecordKind.customFieldDef, _str(e.key, at))] =
          TextFacetState(op: op, value: _str(o['value'], at, allowEmpty: true));
    }
  }
  if (m.containsKey('numberValues')) {
    for (final e in fields('numberValues').entries) {
      final at = 'facets.numberValues.${e.key}';
      final o = _obj(e.value, at, {'op', 'lo', 'hi'});
      final op = _enum(o['op'], [
        CustomFieldOp.eq,
        CustomFieldOp.lt,
        CustomFieldOp.gt,
        CustomFieldOp.between,
      ], at);
      if ((op == CustomFieldOp.between) != o.containsKey('hi')) {
        _bad(at, 'hi belongs to between, and only to it');
      }
      f.numberValues[map(
        SyncRecordKind.customFieldDef,
        _str(e.key, at),
      )] = NumberFacetState(
        op: op,
        lo: _num(o['lo'], at),
        hi: o.containsKey('hi') ? _num(o['hi'], at) : null,
      );
    }
  }
}

void _readByPhrase(Object? v, ByPhraseSelections b) {
  final m = _obj(v, 'byPhrase', {'match', 'exclude'});
  void read(String key, Map<String, List<String>> into) {
    if (!m.containsKey(key)) return;
    final sections = m[key];
    if (sections is! Map) _bad('byPhrase.$key', 'not an object');
    if (sections.length > 50) _bad('byPhrase.$key', 'too many sections');
    for (final e in sections.entries) {
      final at = 'byPhrase.$key.${e.key}';
      final label = _str(e.key, at);
      final moves = _list(e.value, at);
      if (moves.length > 50) _bad(at, 'too many moves');
      into[label] = [for (final x in moves) _str(x, at)];
    }
  }

  read('match', b.match);
  read('exclude', b.exclude);
}

final _paramKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

BuilderNode _readNode(
  Object? v,
  int depth,
  _Budget budget,
  SavedSearchIdMapper map,
  String at,
) {
  if (depth > savedSearchMaxDepth) _bad(at, 'nested too deeply');
  budget.spend(at);
  if (v is! Map) _bad(at, 'not an object');
  switch (v['t']) {
    case 'group':
      final o = _obj(v, at, {'t', 'kind', 'children'});
      final group = BuilderGroup(
        kind: _enum(o['kind'], GroupKind.values, '$at.kind'),
      );
      final children = o.containsKey('children')
          ? _list(o['children'], '$at.children')
          : const <Object?>[];
      for (var i = 0; i < children.length; i++) {
        group.children.add(
          _readNode(children[i], depth + 1, budget, map, '$at.children[$i]'),
        );
      }
      return group;
    case 'figure':
      return _readFigure(v, at);
    case 'tag':
      final o = _obj(v, at, {'t', 'tagId'});
      return BuilderTag(
        tagId: o.containsKey('tagId')
            ? map(SyncRecordKind.tag, _str(o['tagId'], '$at.tagId'))
            : null,
      );
    case 'then':
      final o = _obj(v, at, {'t', 'before', 'after'});
      return BuilderThen(
        before: _readOperand(o['before'], depth + 1, budget, '$at.before'),
        after: _readOperand(o['after'], depth + 1, budget, '$at.after'),
      );
    default:
      return _bad(at, 'unknown row type');
  }
}

BuilderFigure _readFigure(Map<Object?, Object?> v, String at) {
  final o = _obj(v, at, {'t', 'move', 'section', 'params', 'any'});
  final params = <String, Object?>{};
  if (o.containsKey('params')) {
    final p = o['params'];
    if (p is! Map) _bad('$at.params', 'not an object');
    if (p.length > 50) _bad('$at.params', 'too many params');
    for (final e in p.entries) {
      final key = e.key;
      if (key is! String || key.length > 64 || !_paramKey.hasMatch(key)) {
        _bad('$at.params', 'bad param key');
      }
      final value = e.value;
      if (value is String) {
        if (value.length > savedSearchMaxString) {
          _bad('$at.params.$key', 'too long');
        }
      } else if (value is num) {
        if (!value.isFinite) _bad('$at.params.$key', 'not finite');
      } else if (value is! bool) {
        _bad('$at.params.$key', 'not a string, number or boolean');
      }
      params[key] = value;
    }
  }
  return BuilderFigure(
    move: o.containsKey('move') ? _str(o['move'], '$at.move') : null,
    section: o.containsKey('section')
        ? _str(o['section'], '$at.section')
        : null,
    params: params,
    isAnyFigure: o.containsKey('any') && _bool(o['any'], '$at.any'),
  );
}

BuilderFigureNode _readOperand(
  Object? v,
  int depth,
  _Budget budget,
  String at,
) {
  if (depth > savedSearchMaxDepth) _bad(at, 'nested too deeply');
  budget.spend(at);
  if (v is! Map) _bad(at, 'not an object');
  switch (v['t']) {
    case 'figure':
      return _readFigure(v, at);
    case 'figureGroup':
      final o = _obj(v, at, {'t', 'kind', 'children'});
      final group = BuilderFigureGroup(
        kind: _enum(o['kind'], GroupKind.values, '$at.kind'),
      );
      final children = o.containsKey('children')
          ? _list(o['children'], '$at.children')
          : const <Object?>[];
      for (var i = 0; i < children.length; i++) {
        group.children.add(
          _readOperand(children[i], depth + 1, budget, '$at.children[$i]'),
        );
      }
      return group;
    default:
      return _bad(at, 'unknown operand type');
  }
}

// ---------------------------------------------------------------------------
// Writing.
// ---------------------------------------------------------------------------

Map<String, Object?> _encode(
  CollectionPanelState s,
  DateTime today,
  SavedSearchTextCodec text,
) {
  final canonical = _readsDialect(s.scope) ? text.canonicalize(s.text) : s.text;
  final facets = _encodeFacets(s.facets, today);
  final byPhrase = _encodeByPhrase(s.byPhrase);
  return {
    'v': savedSearchFormatVersion,
    if (canonical.trim().isNotEmpty) 'text': canonical,
    if (s.scope != FullTextScope.omni) 'scope': s.scope.name,
    'sort': s.sort.name,
    'sortDirection': s.sortDirection.name,
    if (facets.isNotEmpty) 'facets': facets,
    if (byPhrase.isNotEmpty) 'byPhrase': byPhrase,
    if (s.advanced.children.isNotEmpty) 'advanced': _encodeNode(s.advanced),
  };
}

List<String> _sortedKeys(Map<String, Object?> m) => m.keys.toList()..sort();

List<String> _sortedNames(Iterable<Enum> values) =>
    [for (final e in values) e.name]..sort();

Map<String, Object?> _encodeFacets(FacetSelections f, DateTime today) {
  final months = f.historySince != null
      ? monthsBackFromDate(f.historySince!, today)
      : f.historyMonths;
  List<String> ids(Set<String> s) => s.toList()..sort();
  return {
    if (f.forms.isNotEmpty) 'forms': _sortedNames(f.forms),
    if (f.formations.isNotEmpty) 'formations': _sortedNames(f.formations),
    if (f.progressions.isNotEmpty) 'progressions': _sortedNames(f.progressions),
    if (f.statuses.isNotEmpty) 'statuses': _sortedNames(f.statuses),
    if (f.levels.isNotEmpty) 'levels': ids(f.levels),
    'mixedLevel': ?f.mixedLevel,
    'mixer': ?f.mixer,
    if (f.callStatuses.isNotEmpty)
      'callStatuses': (f.callStatuses.toList()
        ..sort((a, b) => a == b ? 0 : (a ? 1 : -1))),
    if (f.historyVenue != null) 'historyVenue': f.historyVenue!.storageKey,
    'historyMonths': ?months,
    'minRating': ?f.minRating,
    if (f.authorIds.isNotEmpty) 'authorIds': ids(f.authorIds),
    if (f.tagIds.isNotEmpty) 'tagIds': ids(f.tagIds),
    if (!f.tagsMatchAll) 'tagsMatchAll': false,
    if (f.untagged) 'untagged': true,
    if (f.sourceIds.isNotEmpty) 'sourceIds': ids(f.sourceIds),
    if (f.tunes.isNotEmpty) 'tunes': List<String>.of(f.tunes),
    if (f.meters.isNotEmpty) 'meters': ids(f.meters),
    if (f.musicalKeys.isNotEmpty) 'musicalKeys': ids(f.musicalKeys),
    if (f.choiceValues.values.any((v) => v.isNotEmpty))
      'choiceValues': {
        for (final k in _sortedKeys(f.choiceValues))
          if (f.choiceValues[k]!.isNotEmpty) k: ids(f.choiceValues[k]!),
      },
    if (f.booleanValues.isNotEmpty)
      'booleanValues': {
        for (final k in _sortedKeys(f.booleanValues)) k: f.booleanValues[k],
      },
    if (f.textValues.values.any((v) => v.isEffective))
      'textValues': {
        for (final k in _sortedKeys(f.textValues))
          if (f.textValues[k]!.isEffective)
            k: {
              'op': f.textValues[k]!.op.name,
              'value': f.textValues[k]!.value,
            },
      },
    if (f.numberValues.values.any((v) => v.isEffective))
      'numberValues': {
        for (final k in _sortedKeys(f.numberValues))
          if (f.numberValues[k]!.isEffective)
            k: {
              'op': f.numberValues[k]!.op.name,
              'lo': f.numberValues[k]!.lo,
              'hi': ?f.numberValues[k]!.hi,
            },
      },
  };
}

Map<String, Object?> _encodeByPhrase(ByPhraseSelections b) {
  Map<String, Object?> side(Map<String, List<String>> m) => {
    for (final k in _sortedKeys(m))
      if (m[k]!.isNotEmpty) k: List<String>.of(m[k]!),
  };
  final match = side(b.match);
  final exclude = side(b.exclude);
  return {
    if (match.isNotEmpty) 'match': match,
    if (exclude.isNotEmpty) 'exclude': exclude,
  };
}

Map<String, Object?> _encodeNode(BuilderNode n) => switch (n) {
  BuilderGroup() => {
    't': 'group',
    'kind': n.kind.name,
    if (n.children.isNotEmpty)
      'children': [for (final c in n.children) _encodeNode(c)],
  },
  BuilderFigure() => _encodeFigure(n),
  BuilderTag() => {
    't': 'tag',
    if (n.tagId != null && n.tagId!.isNotEmpty) 'tagId': n.tagId,
  },
  BuilderThen() => {
    't': 'then',
    'before': _encodeOperand(n.before),
    'after': _encodeOperand(n.after),
  },
};

Map<String, Object?> _encodeFigure(BuilderFigure f) {
  final params = {
    for (final e in f.params.entries)
      if (e.value != null) e.key: e.value,
  };
  return {
    't': 'figure',
    if (f.move != null) 'move': f.move,
    if (f.section != null) 'section': f.section,
    if (params.isNotEmpty) 'params': params,
    if (f.isAnyFigure) 'any': true,
  };
}

Map<String, Object?> _encodeOperand(BuilderFigureNode n) => switch (n) {
  BuilderFigure() => _encodeFigure(n),
  BuilderFigureGroup() => {
    't': 'figureGroup',
    'kind': n.kind.name,
    if (n.children.isNotEmpty)
      'children': [for (final c in n.children) _encodeOperand(c)],
  },
};
