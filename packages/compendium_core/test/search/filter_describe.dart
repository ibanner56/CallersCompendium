import 'package:compendium_core/compendium_core.dart';

/// A structural description of [f]: two filters are the same search exactly
/// when their descriptions are equal. (The filter classes have no `==`.)
String describeFilter(DanceFilter f) => switch (f) {
  AndFilter() => 'and(${f.children.map(describeFilter).join(', ')})',
  OrFilter() => 'or(${f.children.map(describeFilter).join(', ')})',
  NotFilter() => 'not(${describeFilter(f.child)})',
  FullTextFilter() => 'fts(${f.query}|${f.scope.name})',
  AuthorFilter() => 'author(${f.choreographerId})',
  SourceFilter() => 'source(${f.query})',
  SourceIdFilter() => 'sourceId(${f.sourceId})',
  TunesFilter() => 'tunes(${f.query})',
  MeterFilter() => 'meter(${f.meter})',
  MusicalKeyFilter() => 'key(${f.musicalKey})',
  FormFilter() => 'form(${f.form.name})',
  FormationFilter() => 'formation(${f.shape.name})',
  ProgressionFilter() => 'progression(${f.progression.name})',
  StatusFilter() => 'status(${f.status.name})',
  LevelFilter() => 'level(${f.difficultyLevelId}|${f.op.name})',
  MixedLevelFilter() => 'mixedLevel(${f.mixed})',
  MixerFilter() => 'mixer(${f.mixer})',
  CalledFilter() =>
    'called(${f.called}|caller=${f.callerFilter}|performed=${f.performedOnly}'
        '|dated=${f.requireEventDate}|venue=${f.venue?.storageKey}'
        '|since=${f.since?.toIso8601String()}|program=${f.currentProgramId}'
        '|${f.tracking.recencyRequireEventDate}'
        '${f.tracking.recencyRequirePerformed})',
  RatingFilter() => 'rating(${f.minimum})',
  TagFilter() => 'tag(${f.tagId})',
  UntaggedFilter() => 'untagged',
  CustomFieldFilter() => 'field(${f.fieldId}|${f.op.name}|${f.value})',
  FigureFilter() => 'figure(${_figure(f.query)})',
  ThenFilter() => 'then(${_figure(f.before)} -> ${_figure(f.after)})',
};

String _figure(FigureQuery q) => switch (q) {
  FigureLeaf() =>
    'leaf(${q.move}|${q.section}|'
        '${(q.params.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join(',')})',
  FigureAnd() => 'and(${q.children.map(_figure).join(', ')})',
  FigureOr() => 'or(${q.children.map(_figure).join(', ')})',
  FigureNot() => 'not(${_figure(q.child)})',
};
