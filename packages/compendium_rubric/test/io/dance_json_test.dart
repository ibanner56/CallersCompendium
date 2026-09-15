import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The Baby Rose, verbatim in the upstream dance-record format.
///
/// Kept byte-for-byte as it arrives from the library rather than trimmed to
/// the fields the compiler reads — the point of this fixture is to prove the
/// parser tolerates the whole envelope, so removing the parts it ignores would
/// remove the thing under test.
const String _babyRoseJson = '''
{
  "id": "seed-baby-rose-0002",
  "title": "The Baby Rose",
  "authorIds": ["seed-baby-rose-0001"],
  "form": "contra",
  "formation": { "shape": "dupleImproper", "detail": "improper" },
  "progression": "single",
  "phraseStructure": "",
  "figures": [
    { "schemaVersion": 1, "move": "swing",
      "params": { "who": "neighbors", "prefix": "balance", "beats": 16 } },
    { "schemaVersion": 1, "move": "circle",
      "params": { "turn": "left", "places": 3, "beats": 8 } },
    { "schemaVersion": 1, "move": "do_si_do",
      "params": { "who": "partners", "turn": 1, "beats": 8 } },
    { "schemaVersion": 1, "move": "swing",
      "params": { "who": "partners", "prefix": "balance", "beats": 16 } },
    { "schemaVersion": 1, "move": "chain",
      "params": { "who": "role2s", "hand": "right", "beats": 8 } },
    { "schemaVersion": 1, "move": "star",
      "params": { "hand": "left", "places": 4, "beats": 8 },
      "note": "to new neighbors", "progression": true }
  ],
  "hook": "", "callingNotes": "Imported from ContraDB.", "walkthrough": "",
  "status": "active", "mixedLevel": false, "mixer": false,
  "tunes": [], "customFields": [], "tagIds": [], "links": [],
  "sourceCitations": [],
  "provenance": { "source": "contradb", "externalId": "8",
                  "importedAt": "2020-01-01T00:00:00.000Z",
                  "sourceVersion": "contradb-html" },
  "createdAt": "2020-01-01T00:00:00.000Z",
  "updatedAt": "2020-01-01T00:00:00.000Z"
}
''';

/// Poetry in Motion — a real record using three figures not yet built.
const String _poetryInMotionJson = '''
{
  "id": "fa0c4e49-3067-4c9e-8a9b-63a8314844c5",
  "title": "Poetry in Motion",
  "form": "contra",
  "formation": { "shape": "dupleImproper", "detail": "improper" },
  "progression": "single",
  "figures": [
    { "schemaVersion": 1, "move": "star",
      "params": { "hand": "right", "places": 4, "beats": 8 } },
    { "schemaVersion": 1, "move": "allemande",
      "params": { "who": "neighbors", "hand": "right", "turn": 1.5,
                  "beats": 8 } },
    { "schemaVersion": 1, "move": "shoulder_round",
      "params": { "who": "nextNeighbors", "shoulder": "left", "turn": 1,
                  "beats": 8 } },
    { "schemaVersion": 1, "move": "swing",
      "params": { "who": "neighbors", "beats": 8 },
      "note": "original neighbor" },
    { "schemaVersion": 1, "move": "give_and_take",
      "params": { "who": "role1s", "give": true, "whom": "partners",
                  "beats": 8 } },
    { "schemaVersion": 1, "move": "swing",
      "params": { "who": "partners", "beats": 8 } },
    { "schemaVersion": 1, "move": "chain",
      "params": { "who": "role2s", "hand": "right", "beats": 8 },
      "note": "to neighbor" },
    { "schemaVersion": 1, "move": "star",
      "params": { "hand": "left", "places": 4, "beats": 8 },
      "progression": true }
  ]
}
''';

Dance _parseOk(String json) {
  final result = parseDanceJson(json);
  switch (result) {
    case Ok(:final value):
      return value;
    case Err(:final error):
      fail('expected a parse, got: $error');
  }
}

DanceParseError _parseErr(String json) {
  final result = parseDanceJson(json);
  switch (result) {
    case Ok():
      fail('expected a parse failure');
    case Err(:final error):
      return error;
  }
}

/// Wraps [figures] in a minimal but well-formed record.
String _record(String figures, {String progression = 'single'}) =>
    '''
{
  "title": "T",
  "form": "contra",
  "formation": { "shape": "dupleImproper", "detail": "improper" },
  "progression": "$progression",
  "figures": [$figures]
}
''';

void main() {
  group('parseDanceJson — real records', () {
    test('reads the four fields the compiler needs from a full envelope', () {
      final dance = _parseOk(_babyRoseJson);

      expect(dance.name, 'The Baby Rose');
      expect(dance.formation, FormationType.dupleImproper);
      expect(dance.success, const ProgressionCriterion(count: 1));
      expect(dance.figures, hasLength(6));
    });

    test('carries the progression flag from the figure that holds it', () {
      final dance = _parseOk(_babyRoseJson);

      expect(dance.figures.map((f) => f.progression), [
        false,
        false,
        false,
        false,
        false,
        true,
      ]);
    });

    test('builds the right figures in order', () {
      final dance = _parseOk(_babyRoseJson);

      expect(dance.figures.map((f) => f.name), [
        'swing',
        'circle',
        'do_si_do',
        'swing',
        'chain',
        'star',
      ]);
    });

    test('resolves `turn` per move rather than by a single global rule', () {
      final dance = _parseOk(_babyRoseJson);

      // Same key, two unrelated meanings: a direction on `circle` and a
      // rotation amount on `do_si_do`.
      expect((dance.figures[1].operation as Circle).turn, CircleDirection.left);
      expect((dance.figures[2].operation as DoSiDo).circling, 1);
    });

    test('the parsed dance compiles to its claimed progression', () {
      // The end-to-end proof: an untouched library record goes in, and the
      // oracle agrees the dance achieves the single progression it claims.
      expect(compile(_parseOk(_babyRoseJson)), isA<Compiled>());
    });

    test('names an unbuilt figure instead of skipping it', () {
      // Silently dropping a figure would change the dance and then compare the
      // result against the oracle anyway, reporting a confident wrong answer.
      // `contra_corners` is a genuinely held figure (`docs/taxonomy.md`, Held
      // table): the prior verifier's implementation is a no-op and the
      // Compendium models it as a free-text container, so it has no single
      // fixed permutation to build.
      final error = _parseErr('''
{
  "title": "T",
  "form": "contra",
  "formation": { "shape": "dupleImproper", "detail": "improper" },
  "progression": "single",
  "figures": [ { "move": "contra_corners", "params": { "who": "neighbors" } } ]
}
''');

      expect(error.path, 'figures[0].move');
      expect(error.message, contains('contra_corners'));
    });

    test('Poetry in Motion parses now that its figures are built', () {
      final dance = _parseOk(_poetryInMotionJson);

      expect(dance.figures.map((f) => f.name), [
        'star',
        'allemande',
        'shoulder_round',
        'swing',
        'give_and_take',
        'swing',
        'chain',
        'star',
      ]);
      expect(dance.figures.last.progression, isTrue);
    });

    test('its corrected 1.5 allemande trades the neighbours', () {
      // The imported record carried `turn: 1.25` here, which is a notation
      // fault in the source rather than a real figure -- user-ruled to 1.5, so
      // the half turn swaps the pair and the dance compiles end to end.
      final result = compile(_parseOk(_poetryInMotionJson));

      expect(result, isA<Compiled>());
    });

    test('its nextNeighbors shoulder round needs them already in position', () {
      // The figure reaches one grouping on, which is only danceable once the
      // couples it names are standing beside each other. Straight off the
      // start they are not, so it is refused rather than quietly resolving to
      // no pairs and being compared against the oracle anyway.
      final dance = _parseOk(_poetryInMotionJson);
      final figure = dance.figures[2].operation;

      expect(figure.name, 'shoulder_round');
      final result = figure.apply(dance.instantiate());
      expect(result, isA<Err<Formation, OpError>>());
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.whoMismatch,
      );
    });
  });

  group('parseDanceJson — forward compatibility', () {
    test('ignores unknown top-level and per-figure fields', () {
      final json = '''
{
  "title": "T",
  "form": "contra",
  "formation": { "shape": "dupleImproper", "detail": "improper" },
  "progression": "single",
  "somethingAddedLater": { "nested": [1, 2, 3] },
  "figures": [
    { "move": "stand_still", "params": { "beats": 8 },
      "note": "free text", "aFutureFigureField": true }
  ]
}
''';

      expect(_parseOk(json).figures, hasLength(1));
    });

    test('ignores an unmodelled parameter without dropping the figure', () {
      final dance = _parseOk(
        _record('{"move": "star", "params": {"hand": "left", "styling": "x"}}'),
      );

      expect((dance.figures.single.operation as Star).hand, Hand.left);
    });
  });

  group('parseDanceJson — defaults', () {
    test('omitted parameters take their documented defaults', () {
      // Records omit anything left at its default, so the defaults are load
      // bearing: getting one wrong silently compiles a different dance.
      final dance = _parseOk(_record('{"move": "swing", "params": {}}'));
      final swing = dance.figures.single.operation as Swing;

      expect(swing.who, WhoSet.partners);
      expect(swing.face, FaceDirection.towardSet);
      expect(swing.prefix, 'none');
    });

    test('a bare figure with no params object at all still parses', () {
      final dance = _parseOk(_record('{"move": "circle"}'));
      final circle = dance.figures.single.operation as Circle;

      expect(circle.turn, CircleDirection.left);
      expect(circle.places, 4);
    });

    test('the `unspecified` sentinel is treated as absent', () {
      // Upstream defaults `chain.hand` to this sentinel rather than the
      // role-implied side, so it arrives unstated on ordinary records.
      final dance = _parseOk(
        _record('{"move": "chain", "params": {"hand": "unspecified"}}'),
      );

      expect((dance.figures.single.operation as Chain).hand, Hand.right);
    });

    test('star grip `none` is carried as no stated grip', () {
      final dance = _parseOk(
        _record(
          '{"move": "star", "params": {"hand": "right", '
          '"grip": "none"}}',
        ),
      );

      expect((dance.figures.single.operation as Star).grip, isNull);
    });
  });

  group('parseDanceJson — vocabulary', () {
    test('accepts the upstream camelCase direction spelling', () {
      final dance = _parseOk(
        _record('{"move": "chain", "params": {"dir": "rightDiagonal"}}'),
      );

      expect(
        (dance.figures.single.operation as Chain).dir,
        ChainDirection.rightDiagonal,
      );
    });

    test('accepts the legacy snake_case direction spelling as an alias', () {
      final dance = _parseOk(
        _record('{"move": "chain", "params": {"dir": "right_diagonal"}}'),
      );

      expect(
        (dance.figures.single.operation as Chain).dir,
        ChainDirection.rightDiagonal,
      );
    });

    test('accepts legacy `who` spellings as aliases', () {
      final dance = _parseOk(
        _record('{"move": "chain", "params": {"who": "robins"}}'),
      );

      expect((dance.figures.single.operation as Chain).who, WhoSet.role2s);
    });

    test('reads `endFacing`, the upstream spelling of the swing facing', () {
      final dance = _parseOk(
        _record('{"move": "swing", "params": {"endFacing": "down"}}'),
      );

      expect(
        (dance.figures.single.operation as Swing).face,
        FaceDirection.down,
      );
    });

    test('prefers the upstream spelling when a record carries both', () {
      // Unreachable from real data -- the second spelling in each pair is ours,
      // so no imported record has one -- but it is a rule rather than an
      // accident, and the doc states it, so it is worth pinning down. The
      // parser takes the first key present with the canonical name listed
      // first, which means upstream's spelling wins.
      final dance = _parseOk(
        _record(
          '{"move": "swing", "params": {"endFacing": "down", "face": "up"}}',
        ),
      );

      expect(
        (dance.figures.single.operation as Swing).face,
        FaceDirection.down,
      );
    });

    test('and does the same for the do si do rotation amount', () {
      final dance = _parseOk(
        _record('{"move": "do_si_do", "params": {"turn": 0.5, "circling": 2}}'),
      );

      expect((dance.figures.single.operation as DoSiDo).circling, 0.5);
    });

    test('resolves `endFacing` per move, as it does `turn`', () {
      // The same key, two unrelated domains: a compass direction on a swing
      // and a *person* on a courtesy turn. Unlike `turn`, a global rule here
      // would not silently mis-resolve -- no value is valid for both, so it
      // would fail outright -- but the key still tells you nothing until you
      // know the move.
      final swing = _parseOk(
        _record('{"move": "swing", "params": {"endFacing": "down"}}'),
      );
      final courtesy = _parseOk(
        _record(
          '{"move": "courtesy_turn", "params": {"endFacing": "partners"}}',
        ),
      );

      expect(
        (swing.figures.single.operation as Swing).face,
        FaceDirection.down,
      );
      expect(
        (courtesy.figures.single.operation as CourtesyTurn).endFacing,
        WhoSet.partners,
      );
    });

    test('and refuses the other move\'s value rather than guessing', () {
      // What makes the polymorphism safe to live with. Neither domain is a
      // subset of the other, so naming across them is an unrecognized value,
      // which is a malformed record rather than something to interpret.
      expect(
        _parseErr(
          _record('{"move": "swing", "params": {"endFacing": "partners"}}'),
        ).path,
        'figures[0].params.endFacing',
      );
      expect(
        _parseErr(
          _record('{"move": "courtesy_turn", "params": {"endFacing": "down"}}'),
        ).path,
        'figures[0].params.endFacing',
      );
    });

    test('and `face` likewise, where only one value tells them apart', () {
      // The subtler of the two, because these domains *overlap*: up, down, in
      // and out mean the same on both moves, so three cases in four would work
      // by coincidence under a wrong global rule. Only `along` separates them.
      final gate = _parseOk(
        _record('{"move": "gate", "params": {"face": "along"}}'),
      );

      expect((gate.figures.single.operation as Gate).face, GateFace.along);
      // The refusal names `face`, which is the key on the page - `swing`
      // accepts it as an alias for `endFacing`, and pointing the reader at a
      // key their record does not contain is worse than not pointing at all.
      // The refusal names `face`, which is the key on the page - `swing`
      // accepts it as an alias for `endFacing`, and pointing the reader at a
      // key their record does not contain is worse than not pointing at all.
      expect(
        _parseErr(
          _record('{"move": "swing", "params": {"face": "along"}}'),
        ).path,
        'figures[0].params.face',
      );
    });

    test('a refusal names the alias the author wrote, not the one we prefer', () {
      // The other polymorphic pair, and the case that shows the rule is about
      // the record rather than about `swing`: `do_si_do` reads `turn` first and
      // `circling` second, so each spelling has to blame itself.
      expect(
        _parseErr(
          _record('{"move": "do_si_do", "params": {"circling": "sideways"}}'),
        ).path,
        'figures[0].params.circling',
      );
      expect(
        _parseErr(
          _record('{"move": "do_si_do", "params": {"turn": "sideways"}}'),
        ).path,
        'figures[0].params.turn',
      );
    });

    test('a canonical unspecified value suppresses a legacy spelling', () {
      final dance = _parseOk(
        _record(
          '{"move": "gate", "params": '
          '{"travel": "unspecified", "turn": 0.5}}',
        ),
      );

      expect((dance.figures.single.operation as Gate).turn, isNull);
    });

    test('a legacy pull-by refusal names dir, not its v35 replacement', () {
      expect(
        _parseErr(
          _record(
            '{"move": "pull_by_direction", '
            '"params": {"dir": "sideways"}}',
          ),
        ).path,
        'figures[0].params.dir',
      );
    });

    test('a bare canonical pull-by is deferred rather than guessed', () {
      final error = _parseErr(_record('{"move": "pull_by", "params": {}}'));

      expect(error.deferred, isTrue);
      expect(error.message, contains('who or where'));
    });

    test('an ambiguous pull-by refusal names its authored selector', () {
      final error = _parseErr(
        _record('{"move": "pull_by", "params": {"where": "unspecified"}}'),
      );

      expect(error.deferred, isTrue);
      expect(error.path, 'figures[0].params.where');
    });

    test('a key that is absent falls back to the spelling we document', () {
      // Nothing is written under either alias, so there is no authored
      // spelling to name and the parameter simply takes its default.
      final plain = _parseOk(_record('{"move": "do_si_do", "params": {}}'));
      expect((plain.figures.single.operation as DoSiDo).circling, 1.0);
    });

    test('maps the progression word to a criterion', () {
      expect(
        _parseOk(_record('', progression: 'double')).success,
        const ProgressionCriterion(count: 2),
      );
    });
  });

  group('parseDanceJson — malformed input', () {
    test('reports invalid JSON rather than throwing', () {
      expect(_parseErr('{not json').message, contains('not valid JSON'));
    });

    test('reports a non-object root', () {
      expect(_parseErr('[]').message, contains('object at the root'));
    });

    test('refuses a form this compiler cannot model', () {
      // A square dance has a different geometry; running it through contra
      // hands four would produce a confident, meaningless answer.
      final error = _parseErr(
        '{"form": "square", "formation": {"shape": "dupleImproper"}, '
        '"progression": "single", "figures": []}',
      );

      expect(error.path, 'form');
      expect(error.message, contains('contra-only'));
    });

    test('requires a progression to check against', () {
      final error = _parseErr(
        '{"form": "contra", "formation": {"shape": "dupleImproper"}, '
        '"figures": []}',
      );

      expect(error.path, 'progression');
    });

    test('rejects an unrecognized progression word', () {
      expect(
        _parseErr(_record('', progression: 'sideways')).path,
        'progression',
      );
    });

    test('warns on an unrecognized formation and reads it as the base', () {
      // Not a refusal: the shape vocabulary is owned upstream and grows, and a
      // dance whose own figures establish the arrangement it dances in is
      // fully determined from the base formation whatever the record called
      // it. The warning is what keeps the substitution from being silent.
      final dance = _parseOk(
        '{"form": "contra", "formation": {"shape": "hexagon"}, '
        '"progression": "single", "figures": []}',
      );

      expect(dance.formation, FormationType.dupleImproper);
      expect(dance.warnings, hasLength(1));
      expect(dance.warnings.single.kind, WarningKind.unrecognizedFormation);
      expect(dance.warnings.single.message, contains('hexagon'));
    });

    test('and that warning survives into the compile result', () {
      // A parse-time diagnostic nobody reports is a diagnostic that does not
      // exist, so the channel from the record to the result is what is under
      // test here rather than the reading itself.
      final dance = _parseOk(
        '{"form": "contra", "formation": {"shape": "hexagon"}, '
        '"progression": "single", "figures": '
        '[{"move": "star", "params": {"hand": "left", "places": 4}, '
        '"progression": true}]}',
      );
      final result = compile(dance);

      expect(
        result.warnings.map((warning) => warning.kind),
        contains(WarningKind.unrecognizedFormation),
      );
    });

    test('but a missing formation shape is still refused', () {
      // The fallback is for a shape this compiler does not *model*. A record
      // with no shape at all has not made a claim to fall back from, and
      // guessing one would invent the dance's starting matrix outright.
      final error = _parseErr(
        '{"form": "contra", "formation": {}, '
        '"progression": "single", "figures": []}',
      );

      expect(error.path, 'formation.shape');
    });

    test('rejects a parameter of the wrong type', () {
      final error = _parseErr(
        _record('{"move": "circle", "params": {"places": "many"}}'),
      );

      expect(error.path, 'figures[0].params.places');
      expect(error.message, contains('whole number'));
    });

    test('rejects an out-of-vocabulary parameter value', () {
      final error = _parseErr(
        _record('{"move": "circle", "params": {"turn": "sideways"}}'),
      );

      expect(error.path, 'figures[0].params.turn');
      expect(error.message, contains('unrecognized'));
    });

    test('locates the failing figure by index', () {
      final error = _parseErr(
        _record('{"move": "stand_still"}, {"move": "nope"}'),
      );

      expect(error.path, 'figures[1].move');
    });

    test('reports a missing figure list', () {
      expect(
        _parseErr(
          '{"form": "contra", "formation": {"shape": "dupleImproper"}, '
          '"progression": "single"}',
        ).path,
        'figures',
      );
    });
  });

  group('parseDanceJson — what counts as deferred', () {
    // The `deferred` flag is what separates the backlog from the defects in a
    // corpus report (`CorpusReport.inScope`). It means "the record is fine and
    // this compiler is the thing missing", so it is set only where the reason
    // is that something is not modelled yet -- never where the record is
    // malformed, because no amount of implementation work would fix that.

    test('an unimplemented move is deferred', () {
      final error = _parseErr(_record('{"move": "promenade"}'));

      expect(error.path, 'figures[0].move');
      expect(error.deferred, isTrue);
    });

    test('a vocabulary value with no reading here is deferred', () {
      // `shadows` is the corpus's largest one: a real dancer set this compiler
      // does not model, on a figure it otherwise implements.
      final error = _parseErr(
        _record('{"move": "swing", "params": {"who": "shadows"}}'),
      );

      expect(error.path, 'figures[0].params.who');
      expect(error.deferred, isTrue);
    });

    test('a malformed value is NOT deferred, however it fails', () {
      // The boundary that keeps the flag meaningful. Both of these refuse at a
      // figure, and neither is waiting on implementation work.
      expect(
        _parseErr(
          _record('{"move": "circle", "params": {"places": "many"}}'),
        ).deferred,
        isFalse,
      );
      expect(_parseErr(_record('{"move": 7}')).deferred, isFalse);
    });

    test('an unmodelled progression tier is NOT deferred', () {
      // Deliberate, and the reason the flag is per-figure rather than
      // per-dance: this compiler does not model a `none` or `other`
      // progression, but that is a property of the dance rather than of any
      // figure in it. Counting it here would widen "deferred" past the scope
      // the user set, and would quietly shrink the denominator.
      final error = _parseErr(_record('', progression: 'sideways'));

      expect(error.path, 'progression');
      expect(error.deferred, isFalse);
    });
  });
}
