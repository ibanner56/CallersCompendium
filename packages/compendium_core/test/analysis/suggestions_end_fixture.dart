// The fixture behind the end-of-program regression test (#2344): a program
// with an alternate, a note and a break, and candidates that each factor
// moves, so that the order pinned in suggestions_end_regression_test.dart
// exercises every factor at once.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';

final _stamp = DateTime.utc(2026, 1, 1);

/// A fixed calendar day: the fixture never reads the real clock.
final endFixtureToday = DateTime.utc(2026, 11, 23);

Figure _fig(String move, int beats) =>
    testFigure(move: move, params: {'beats': beats});

Dance _dance(
  String id,
  List<Figure> figures, {
  DanceForm form = DanceForm.contra,
  FormationShape shape = FormationShape.dupleImproper,
  String? level,
}) => Dance(
  id: id,
  title: id,
  form: form,
  formation: Formation(shape),
  figures: figures,
  difficultyLevelId: level,
  createdAt: _stamp,
  updatedAt: _stamp,
);

final endFixtureProgram = <Dance>[
  _dance('p-a', [
    _fig('circle', 16),
    _fig('swing', 16),
  ], level: DifficultyLevel.beginnerId),
  _dance(
    'p-b',
    [_fig('do_si_do', 16), _fig('swing', 16)],
    shape: FormationShape.becketCw,
    level: DifficultyLevel.intermediateId,
  ),
  _dance('p-b-alt', [
    _fig('petronella', 16),
    _fig('swing', 16),
  ], level: DifficultyLevel.intermediateId),
  _dance('p-c', [
    _fig('right_left_through', 16),
    _fig('swing', 16),
  ], level: DifficultyLevel.intermediateId),
  _dance(
    'p-d',
    [_fig('swing', 16), _fig('circle', 16)],
    shape: FormationShape.becketCcw,
    level: DifficultyLevel.advancedId,
  ),
];

/// a, b (with its alternate), a note, a break, c, d.
final endFixtureSlots = <ProgramSlot>[
  ProgramSlot(id: 's-a', position: 0, danceId: 'p-a'),
  ProgramSlot(id: 's-b', position: 1, danceId: 'p-b'),
  ProgramSlot(id: 's-b-alt', position: 2, danceId: 'p-b-alt', isAlt: true),
  ProgramSlot(id: 's-note', position: 3, text: 'Waltz'),
  ProgramSlot(id: 's-break', position: 4, text: Program.breakSlotText),
  ProgramSlot(id: 's-c', position: 5, danceId: 'p-c'),
  ProgramSlot(id: 's-d', position: 6, danceId: 'p-d'),
];

final endFixtureCandidates = <Dance>[
  _dance('c-overlap', [
    _fig('circle', 16),
    _fig('swing', 16),
  ], level: DifficultyLevel.advancedId),
  _dance(
    'c-becket',
    [_fig('petronella', 16), _fig('do_si_do', 16)],
    shape: FormationShape.becketCw,
    level: DifficultyLevel.intermediateId,
  ),
  _dance('c-fresh', [
    _fig('right_left_through', 8),
    _fig('petronella', 8),
    _fig('do_si_do', 16),
  ], level: DifficultyLevel.beginnerId),
  _dance(
    'c-triplet',
    [_fig('swing', 8), _fig('circle', 24)],
    shape: FormationShape.triplet,
    level: DifficultyLevel.intermediateId,
  ),
  _dance('c-english', const [], form: DanceForm.ecd),
  _dance('c-square', [_fig('swing', 16)], form: DanceForm.square),
  endFixtureProgram[1],
  _dance('c-recent', [
    _fig('do_si_do', 24),
    _fig('swing', 8),
  ], level: DifficultyLevel.advancedId),
  _dance('c-long-ago', [
    _fig('swing', 8),
    _fig('do_si_do', 24),
  ], level: DifficultyLevel.advancedId),
  _dance('c-no-level', [_fig('circle', 16), _fig('do_si_do', 16)]),
  _dance('c-new-moves', [
    _fig('long_lines', 8),
    _fig('pass_through', 8),
    _fig('do_si_do', 16),
  ], level: DifficultyLevel.intermediateId),
  _dance(
    'c-proper',
    [_fig('petronella', 16), _fig('swing', 16)],
    shape: FormationShape.dupleProper,
    level: DifficultyLevel.beginnerId,
  ),
];

final endFixtureCalledHere = <String, DateTime?>{
  'c-recent': DateTime.utc(2026, 11, 2),
  'c-long-ago': DateTime.utc(2025, 3, 8),
  'c-no-level': null,
};

/// Ten more dances, for an evening longer than the curve's nominal 12.
final _moreDances = <Dance>[
  for (var i = 0; i < 10; i++)
    _dance('p-more-$i', [
      _fig(i.isEven ? 'long_lines' : 'pass_through', 16),
    ], level: DifficultyLevel.intermediateId),
];

/// The end-of-program request for [settings] under [mode]; with [long], the
/// program goes on for ten more dances.
SuggestionRequest endFixtureRequest({
  SuggestionSettings settings = SuggestionSettings.defaults,
  MatrixCollisionMode mode = MatrixCollisionMode.exactBeats,
  bool hasVenue = true,
  bool long = false,
}) => SuggestionRequest(
  slotsBefore: [
    ...endFixtureSlots,
    if (long)
      for (var i = 0; i < _moreDances.length; i++)
        ProgramSlot(
          id: 's-more-$i',
          position: endFixtureSlots.length + i,
          danceId: _moreDances[i].id,
        ),
  ],
  programDances: {
    for (final d in [...endFixtureProgram, if (long) ..._moreDances])
      d.id: SuggestionCandidate.fromDance(d),
  },
  candidates: [
    for (final d in endFixtureCandidates) SuggestionCandidate.fromDance(d),
  ],
  settings: settings,
  today: endFixtureToday,
  collisionMode: mode,
  taxonomy: shippedTaxonomies.anyForm,
  levels: DifficultyLevel.shipped,
  hasVenue: hasVenue,
  calledHere: endFixtureCalledHere,
);

/// The settings variants the regression test pins.
final endFixtureVariants = <String, SuggestionRequest Function()>{
  'defaults': endFixtureRequest,
  'phrase rule': () => endFixtureRequest(mode: MatrixCollisionMode.phrase),
  'even curve, no venue': () => endFixtureRequest(
    settings: SuggestionSettings.defaults.copyWith(
      curveShape: DifficultyCurveShape.even,
    ),
    hasVenue: false,
  ),
  'a long evening': () => endFixtureRequest(long: true),
  'every factor a lot': () {
    var settings = SuggestionSettings.defaults;
    for (final f in SuggestionFactor.values) {
      settings = settings.withWeight(f, SuggestionWeight.aLot);
    }
    return endFixtureRequest(settings: settings);
  },
};
