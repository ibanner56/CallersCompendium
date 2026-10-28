import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

/// #1972: a `.USR` dance's formation comes from its separate columns, `Type`,
/// `Formation`, `ContraForm`, `Direction` and `FormationOther`, not from the
/// first non-empty one. The cases are the column combinations of a beta
/// tester's library, each with the dance it came from.
void main() {
  Dance map(Map<String, String> columns) => mapCallersCompanionDance(
    ccDanceRecordFromColumns({'Name': 'D', ...columns}),
  ).dance;

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

  test('a square is a square dance, and a mixer SubType makes it a mixer', () {
    // Head for Home; The Auctioneer.
    expectFormation(
      {'Type': 'Square', 'Formation': 'Square', 'SubType': 'Keeper, H S H S'},
      FormationShape.other,
      detail: 'Square',
      form: DanceForm.square,
    );
    expectFormation(
      {
        'Type': 'Square',
        'Formation': 'Square',
        'ContraForm': 'Improper',
        'SubType': 'Mixer, H H S S',
      },
      FormationShape.other,
      detail: 'Square',
      mixer: true,
      form: DanceForm.square,
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

  test('a recognised type adds no "Type:" line to the calling notes', () {
    final d = map({'Type': 'Circle Mixer', 'Formation': 'Duple Minor'});
    expect(d.callingNotes, isNot(contains('Type:')));
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
