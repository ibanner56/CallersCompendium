import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1972: a `.USR` dance's formation comes from its separate columns, `Type`,
/// `Formation`, `ContraForm`, `Direction` and `FormationOther`, not from the
/// first non-empty one. The cases are the column combinations of a beta
/// tester's library, each with the dance it came from, read through the
/// adapter's parse path (the columns the fetch stage serialises).
void main() {
  final adapter = CallersCompanionUsrAdapter();
  StructuredDraft parse(Map<String, String> columns) => adapter.parse(
    RawRecord(
      source: ProvenanceSource.callersCompanion,
      externalId: '7',
      sourceVersion: CallersCompanionUsrAdapter.sourceVersion,
      payload: jsonEncode({
        'rowId': '7',
        'columns': {'Name': 'D', ...columns},
      }),
      contentType: 'application/json',
    ),
  );
  Dance map(Map<String, String> columns) => parse(columns).dance;

  void expectFormation(
    Map<String, String> columns,
    FormationShape shape, {
    String? detail,
    bool mixer = false,
    DanceForm form = DanceForm.contra,
  }) {
    final d = map(columns);
    expect(d.formation.shape, shape, reason: '$columns');
    expect(d.formation.detail, detail, reason: '$columns');
    expect(d.mixer, mixer, reason: '$columns');
    expect(d.form, form, reason: '$columns');
  }

  test('a Becket reads its direction', () {
    // Balance to my Lou.
    expectFormation({
      'Type': 'Contra',
      'Formation': 'Duple Minor',
      'ContraForm': 'Becket',
      'Direction': 'CCW',
    }, FormationShape.becketCcw);
    expectFormation({
      'Type': 'Contra',
      'Formation': 'Duple Minor',
      'ContraForm': 'Becket',
      'Direction': 'CW',
    }, FormationShape.becketCw);
  });

  test('the Formation family decides the shape over ContraForm', () {
    // Grand Square Contra; Ted's Triplet #7.
    expectFormation({
      'Type': 'Contra',
      'Formation': 'Four Facing Four',
      'ContraForm': 'Improper',
    }, FormationShape.fourFaceFour);
    expectFormation({
      'Type': 'Contra',
      'Formation': 'Triplet',
      'ContraForm': 'Improper',
    }, FormationShape.triplet);
    // Elegance and Simplicity (original Triple).
    expectFormation(
      {'Type': 'Contra', 'Formation': 'Triple Minor', 'ContraForm': 'Improper'},
      FormationShape.tripleMinor,
      detail: 'Improper',
    );
  });

  test('mixer types are mixers in their formation', () {
    // La Bastringue; Old Bob's Mixer (no ContraForm).
    expectFormation(
      {
        'Type': 'Circle Mixer',
        'Formation': 'Duple Minor',
        'ContraForm': 'Improper',
      },
      FormationShape.circleMixer,
      mixer: true,
    );
    expectFormation(
      {'Type': 'Circle Mixer', 'Formation': 'Duple Minor'},
      FormationShape.circleMixer,
      mixer: true,
    );
    // Easy Three Person Mixer.
    expectFormation(
      {
        'Type': 'Scatter Mixer',
        'Formation': 'Other',
        'ContraForm': 'Improper',
        'FormationOther': 'Triads',
      },
      FormationShape.scatterMixer,
      detail: 'Triads',
      mixer: true,
    );
  });

  test('a longways type is longways', () {
    // Virginia Reel.
    expectFormation(
      {
        'Type': 'Longways',
        'Formation': 'Other',
        'ContraForm': 'Proper',
        'FormationOther': 'Six couples (or so)',
      },
      FormationShape.longways,
      detail: 'Six couples (or so)',
    );
  });

  test('a square is a square dance in a square set, and a mixer SubType '
      'makes it a mixer (pre-release audit finding B-02)', () {
    // Head for Home; The Auctioneer.
    expectFormation(
      {'Type': 'Square', 'Formation': 'Square', 'SubType': 'Keeper, H S H S'},
      FormationShape.square,
      form: DanceForm.square,
    );
    expectFormation(
      {
        'Type': 'Square',
        'Formation': 'Square',
        'ContraForm': 'Improper',
        'SubType': 'Mixer, H H S S',
      },
      FormationShape.square,
      detail: 'Improper',
      mixer: true,
      form: DanceForm.square,
    );
  });

  test("a square's formation is one of a square's shapes (ADR-007 §8.1, "
      'pre-release audit finding B-02)', () {
    // No formation at all is a square set, not contra's improper default.
    expectFormation(
      {'Type': 'Square'},
      FormationShape.square,
      form: DanceForm.square,
    );
    // A big circle keeps the circle, which squares use for it.
    final big = map({'Type': 'Square', 'Formation': 'Circle'});
    expect(big.formation.shape, FormationShape.circle);
    // Whatever the columns say, the shape is one a square offers, and the
    // words the source gave stay in the detail.
    for (final columns in const [
      {'Type': 'Square', 'Formation': 'Hexagon'},
      {'Type': 'Square', 'Formation': 'Duple Minor', 'ContraForm': 'Becket'},
      {'Type': 'Square', 'FormationOther': 'Four couples'},
    ]) {
      final dance = map(columns);
      expect(dance.form, DanceForm.square, reason: '$columns');
      expect(
        squareFormationShapes,
        contains(dance.formation.shape),
        reason: '$columns',
      );
      expect(dance.formation.improper, isFalse, reason: '$columns');
    }
    // A family that names another shape is `other`, its words the detail.
    expectFormation(
      {'Type': 'Square', 'Formation': 'Hexagon'},
      FormationShape.other,
      detail: 'Hexagon',
      form: DanceForm.square,
    );
    expectFormation(
      {'Type': 'Square', 'Formation': 'Four Facing Four'},
      FormationShape.other,
      detail: 'Four Facing Four',
      form: DanceForm.square,
    );
    // A start alone names no shape: still a square set, the start kept.
    for (final start in const ['Improper', 'Proper', 'Indecent']) {
      expectFormation(
        {'Type': 'Square', 'ContraForm': start},
        FormationShape.square,
        detail: start,
        form: DanceForm.square,
      );
    }
    expectFormation(
      {'Type': 'Square', 'ContraForm': 'Improper', 'Direction': 'Rev'},
      FormationShape.square,
      detail: 'Improper; Rev',
      form: DanceForm.square,
    );
  });

  test("a square in a big circle keeps the source's words and start "
      '(pre-release audit finding B-02)', () {
    expectFormation(
      {'Type': 'Square', 'FormationOther': 'Big circle, Kentucky running set'},
      FormationShape.circle,
      detail: 'Big circle, Kentucky running set',
      form: DanceForm.square,
    );
    expect(
      map({
        'Type': 'Square',
        'Formation': 'Circle',
        'ContraForm': 'Improper',
      }).formation.detail,
      contains('Improper'),
    );
  });

  test("a text export's square in a circle mixer is a mixer in a circle "
      '(pre-release audit finding B-02)', () {
    final dance = mapCallersCompanionDance(
      CcDanceRecord(name: 'M', type: 'Square', formation: 'Circle mixer'),
    ).dance;
    expect(dance.form, DanceForm.square);
    expect(dance.formation.shape, FormationShape.circle);
    expect(dance.formation.detail, 'Circle mixer');
    expect(dance.mixer, isTrue);
  });

  test("a square's SubType names its repeat order (ADR-007 §8.1)", () {
    expect(
      map({'Type': 'Square', 'SubType': 'Keeper, H S H S'}).repeatOrder,
      SquareRepeatOrder.headsSidesHeadsSides,
    );
    expect(
      map({'Type': 'Square', 'SubType': 'Mixer, H H S S'}).repeatOrder,
      SquareRepeatOrder.headsHeadsSidesSides,
    );
    // No order after the comma, or one this reading does not know, states
    // nothing rather than guessing.
    for (final subType in ['Keeper', 'Keeper, ', 'Mixer, H S S H']) {
      expect(
        map({'Type': 'Square', 'SubType': subType}).repeatOrder,
        SquareRepeatOrder.unstated,
        reason: subType,
      );
    }
    // Only a square has a repeat order.
    expect(
      map({'Type': 'Contra', 'SubType': 'Keeper, H S H S'}).repeatOrder,
      SquareRepeatOrder.unstated,
    );
  });

  test('FormationOther is the detail', () {
    // Levi Jackson Rag; United We Dance.
    expectFormation(
      {
        'Type': 'Other',
        'Formation': 'Other',
        'ContraForm': 'Improper',
        'FormationOther': 'Five couple horseshoe',
      },
      FormationShape.other,
      detail: 'Five couple horseshoe',
    );
    expectFormation(
      {
        'Type': 'Contra',
        'Formation': 'Duple Minor',
        'ContraForm': 'Improper',
        'FormationOther': 'Long Waves, R-hand to Neighbor',
      },
      FormationShape.dupleImproper,
      detail: 'Long Waves, R-hand to Neighbor',
    );
  });

  test(
    'Rev is a reverse-progression improper; other directions are ignored',
    () {
      // Cup of Joe; My Marbles Have Many Moods; Truffles for Breakfast.
      expectFormation({
        'Type': 'Contra',
        'Formation': 'Duple Minor',
        'ContraForm': 'Improper',
        'Direction': 'Rev',
      }, FormationShape.reverseProgressionImproper);
      expectFormation({
        'Type': 'Contra',
        'Formation': 'Duple Minor',
        'ContraForm': 'Indecent',
        'Direction': 'Std',
      }, FormationShape.dupleIndecent);
      expectFormation({
        'Type': 'Contra',
        'Formation': 'Duple Minor',
        'ContraForm': 'Indecent',
        'Direction': 'N/A',
      }, FormationShape.dupleIndecent);
    },
  );

  test('a formation type adds no "Type:" line to the calling notes', () {
    for (final type in ['Circle Mixer', 'Scatter Mixer', 'Longways']) {
      final draft = parse({'Type': type, 'Formation': 'Other'});
      expect(draft.dance.callingNotes, isNot(contains('Type:')), reason: type);
      expect(
        draft.issues.map((i) => i.code),
        isNot(contains('cc_unmapped_type')),
        reason: type,
      );
    }
  });

  test('the type and SubType count without any formation column', () {
    expectFormation({'Type': 'Longways'}, FormationShape.longways);
    expectFormation(
      {'Type': 'Circle Mixer'},
      FormationShape.circleMixer,
      mixer: true,
    );
    final square = map({'Type': 'Square', 'SubType': 'Mixer, H H S S'});
    expect(square.mixer, isTrue);
    expect(square.form, DanceForm.square);
  });

  test('a description alone is read as the text export reads it', () {
    expectFormation({
      'FormationOther': 'Sicilian Circle',
    }, FormationShape.sicilianCircle);
    expectFormation({'FormationOther': 'Becket'}, FormationShape.becketCw);
    final draft = parse({'FormationOther': 'Five couple horseshoe'});
    expect(draft.dance.formation.shape, FormationShape.other);
    expect(draft.dance.formation.detail, 'Five couple horseshoe');
    expect(draft.issues.map((i) => i.code), contains('cc_unmapped_formation'));
  });

  test('a start CC does not offer is read as the text export reads it', () {
    expectFormation({
      'ContraForm': 'Sicilian Circle',
    }, FormationShape.sicilianCircle);
    expectFormation({'ContraForm': 'Triple Minor'}, FormationShape.tripleMinor);
    final draft = parse({'ContraForm': 'Long lines facing'});
    expect(draft.dance.formation.shape, FormationShape.other);
    expect(draft.dance.formation.detail, 'Long lines facing');
    expect(draft.issues.map((i) => i.code), contains('cc_unmapped_formation'));
  });

  test('a family CC does not offer is read as the text export reads it', () {
    expectFormation({'Formation': 'Becket'}, FormationShape.becketCw);
    expectFormation(
      {'Formation': 'Sicilian Circle', 'FormationOther': 'Facing pairs'},
      FormationShape.sicilianCircle,
      detail: 'Facing pairs',
    );
  });

  test('the text export keeps its single formation string and Type note', () {
    final mapping = mapCallersCompanionDance(
      CcDanceRecord(name: 'D', type: 'Circle Mixer', formation: 'Improper'),
    );
    expect(mapping.dance.formation.shape, FormationShape.dupleImproper);
    expect(mapping.dance.mixer, isFalse);
    expect(mapping.dance.callingNotes, contains('Type: Circle Mixer'));
    expect(mapping.issues.map((i) => i.code), contains('cc_unmapped_type'));
  });

  test('a set item marked ALT is an alternate', () {
    final archive = extractCcUsrArchive(
      FmpDatabase(
        versionNum: 12,
        creator: 'test',
        warnings: const [],
        tables: [
          FmpTable(
            1,
            'Dance',
            [FmpColumn(1, 'zk_Dance_ID'), FmpColumn(2, 'Name')],
            [
              FmpRecord(10, {1: '4', 2: 'A'}),
              FmpRecord(11, {1: '7', 2: 'B'}),
            ],
          ),
          FmpTable(
            2,
            'Set',
            [FmpColumn(1, 'zk_Set_ID'), FmpColumn(2, 'Location')],
            [
              FmpRecord(20, {1: '1', 2: 'Hall'}),
            ],
          ),
          FmpTable(
            3,
            'SetItem',
            [
              FmpColumn(1, 'zk_Set_ID'),
              FmpColumn(2, 'zk_Dance_ID'),
              FmpColumn(3, 'Order'),
              FmpColumn(4, 'AlternateDance'),
            ],
            [
              FmpRecord(30, {1: '1', 2: '4', 3: '1'}),
              FmpRecord(31, {1: '1', 2: '7', 3: '2', 4: 'ALT'}),
            ],
          ),
        ],
      ),
    );
    final items = archive.sets.single.items;
    expect(items.map((i) => i.isAlt), [false, true]);
  });
}
