import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// The Repertoire page's aggregates (#2357) must agree with the rest of the
/// app: a dance's "All time" count is its Collection row's "called ×N", a
/// window selects what the Called filter's Within selects, and Never called is
/// what the Not called filter lists.
void main() {
  final now = DateTime.utc(2026, 11, 22, 12);
  // "Within 3 months" of 2026-11-22.
  final cutoff = DateTime.utc(2026, 8, 22);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;
  late RepertoireRepository repertoire;

  void open(CompendiumDatabase database) {
    db = database;
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    repertoire = RepertoireRepository(db);
  }

  tearDown(() => db.close());

  Future<void> dance(
    String id, {
    DanceForm form = DanceForm.contra,
    FormationShape shape = FormationShape.dupleImproper,
    List<String> authors = const [],
    List<Figure> figures = const [],
  }) => dances.create(
    Dance(
      id: id,
      title: id,
      form: form,
      formation: Formation(shape),
      authorIds: authors,
      figures: figures,
      createdAt: now,
      updatedAt: now,
    ),
  );

  var slotSeq = 0;
  ProgramSlot slot(
    String danceId, {
    DateTime? performedAt,
    bool isAlt = false,
  }) => ProgramSlot(
    id: 's${slotSeq++}',
    position: slotSeq,
    danceId: danceId,
    performedAt: performedAt,
    isAlt: isAlt,
  );

  Future<void> program(
    String id, {
    String? venue,
    String? venueId,
    String? caller,
    DateTime? eventDate,
    DateTime? updatedAt,
    required List<ProgramSlot> slots,
  }) => programs.create(
    Program(
      id: id,
      title: id,
      venue: venue,
      venueId: venueId,
      caller: caller,
      eventDate: eventDate,
      slots: slots,
      createdAt: DateTime.utc(2020),
      updatedAt: updatedAt ?? DateTime.utc(2020),
    ),
  );

  /// Seeds choreographers by name; each id is the lower-cased name.
  Future<void> choreographers(String a, [String? b]) async {
    for (final name in [a, ?b]) {
      final _ = await ChoreographerRepository(
        db,
      ).upsert(Choreographer(id: name.toLowerCase(), name: name));
    }
  }

  Future<Set<String>> search(DanceFilter filter) async =>
      (await dances.search(filter)).toSet();

  /// Every gate combination the calling-history settings can make: performed
  /// required, event date required, and the caller scope.
  final scopes = [
    for (final performedOnly in [false, true])
      for (final requireEventDate in [false, true])
        for (final caller in [null, 'Alice'])
          (
            performedOnly: performedOnly,
            requireEventDate: requireEventDate,
            caller: caller,
          ),
  ];

  /// A collection that splits every gate: dated and undated programs,
  /// performed and unperformed slots, alternates, two callers and an
  /// unattributed program, a trashed program, and a trashed dance.
  Future<void> mixedFixture() async {
    await choreographers('Kaynor');
    for (final id in ['a', 'b', 'c', 'd', 'never']) {
      await dance(id, authors: id == 'a' ? ['kaynor'] : const []);
    }
    await dance('gone');
    final performed = DateTime.utc(2026, 10, 1, 21);
    await program(
      'dated-alice',
      caller: 'Alice',
      eventDate: DateTime.utc(2026, 10, 1),
      slots: [
        slot('a', performedAt: performed),
        slot('a'),
        slot('b'),
        slot('c', isAlt: true),
        slot('d', isAlt: true, performedAt: performed),
        slot('gone'),
      ],
    );
    await program(
      'undated-bob',
      caller: 'Bob',
      slots: [
        slot('a'),
        slot('b', performedAt: performed),
      ],
    );
    await program(
      'undated-unattributed',
      slots: [
        slot('c', performedAt: performed),
        slot('d'),
      ],
    );
    await program(
      'trashed',
      eventDate: DateTime.utc(2026, 10, 2),
      slots: [slot('never', performedAt: performed)],
    );
    await programs.softDelete('trashed', at: now);
    await dances.softDelete('gone', at: now);
  }

  group('agreement with the rest of the app', () {
    setUp(() => open(openTestDatabase()));

    test('each dance\'s all-time count is countByDance under every '
        'combination of the calling-history settings', () async {
      await mixedFixture();
      for (final s in scopes) {
        final expected = {
          for (final MapEntry(:key, :value) in (await programs.countByDance(
            callerFilter: s.caller,
          )).entries)
            if (value.countFor(
                  s.performedOnly,
                  requireEventDate: s.requireEventDate,
                )
                case final n when n > 0 && key != 'gone')
              key: n,
        };
        final stats = await repertoire.load(
          RepertoireScope(
            performedOnly: s.performedOnly,
            requireEventDate: s.requireEventDate,
            callerFilter: s.caller,
          ),
        );
        expect(stats.callCounts, expected, reason: '$s');
        // The fixture must split the settings, or this proves nothing.
        expect(expected, isNotEmpty, reason: '$s');
      }
      // ...and it does: the four gate pairs give four different maps.
      final distinct = {
        for (final s in scopes.where((s) => s.caller == null))
          (await repertoire.load(
            RepertoireScope(
              performedOnly: s.performedOnly,
              requireEventDate: s.requireEventDate,
            ),
          )).callCounts.toString(),
      };
      expect(distinct, hasLength(4));
    });

    test('Never called is what the Not called filter lists, under every '
        'combination of the settings', () async {
      await mixedFixture();
      for (final s in scopes) {
        final notCalled = await search(
          CalledFilter(
            called: false,
            performedOnly: s.performedOnly,
            requireEventDate: s.requireEventDate,
            callerFilter: s.caller,
          ),
        );
        final stats = await repertoire.load(
          RepertoireScope(
            performedOnly: s.performedOnly,
            requireEventDate: s.requireEventDate,
            callerFilter: s.caller,
          ),
          sampleCount: 100,
        );
        expect(stats.neverCalledCount, notCalled.length, reason: '$s');
        expect(
          stats.neverCalledSample.map((d) => d.danceId).toSet(),
          notCalled,
          reason: '$s',
        );
      }
    });

    group('a window selects what CalledFilter.since selects', () {
      // Calls on the cutoff day and one day before it, under each recency
      // toggle: an undated program is dated by its last edit only while
      // recency does not require an event date.
      Future<void> boundaryFixture() async {
        for (final id in ['on', 'before', 'undated-edit', 'unperformed']) {
          await dance(id);
        }
        await program(
          'p-on',
          eventDate: cutoff,
          slots: [slot('on', performedAt: cutoff)],
        );
        await program(
          'p-before',
          eventDate: cutoff.subtract(const Duration(days: 1)),
          slots: [slot('before')],
        );
        await program(
          'p-undated',
          updatedAt: cutoff.add(const Duration(days: 3)),
          slots: [slot('undated-edit')],
        );
        await program(
          'p-unperformed',
          eventDate: cutoff.add(const Duration(days: 5)),
          slots: [slot('unperformed')],
        );
      }

      for (final tracking in [
        CallingHistoryTracking.defaults,
        const CallingHistoryTracking(recencyRequireEventDate: false),
        const CallingHistoryTracking(recencyRequirePerformed: true),
      ]) {
        test('recency event date ${tracking.recencyRequireEventDate}, '
            'performed ${tracking.recencyRequirePerformed}', () async {
          await boundaryFixture();
          final called = await search(
            CalledFilter(called: true, since: cutoff, tracking: tracking),
          );
          final notCalled = await search(
            CalledFilter(called: false, since: cutoff, tracking: tracking),
          );
          final stats = await repertoire.load(
            RepertoireScope(since: cutoff, tracking: tracking),
            sampleCount: 100,
          );
          expect(stats.callCounts.keys.toSet(), called);
          expect(stats.notCalledInWindowCount, notCalled.length);
          expect(
            stats.notCalledInWindowSample.map((d) => d.danceId).toSet(),
            notCalled,
          );
          // The boundary: a call on the cutoff day is in, one a day earlier
          // is out.
          expect(called, isNot(contains('before')));
          if (!tracking.recencyRequirePerformed) {
            expect(called, contains('on'));
          }
        });
      }

      test('rejects a cutoff that is not a UTC calendar date', () async {
        expect(
          () => repertoire.load(RepertoireScope(since: DateTime(2026, 8, 22))),
          throwsArgumentError,
        );
      });
    });
  });

  group('read-only', () {
    setUp(() => open(openTestDatabase()));

    test('load writes nothing to the database', () async {
      await mixedFixture();
      Future<int> changes() async =>
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      final before = await changes();
      await repertoire.load(RepertoireScope(since: cutoff));
      await repertoire.load(
        const RepertoireScope(performedOnly: true, form: DanceForm.contra),
      );
      expect(await changes(), before);
    });
  });

  group('sections', () {
    setUp(() => open(openTestDatabase()));

    test('figure frequency counts each dance once per move, by type', () async {
      await dance(
        'two-swings',
        figures: [
          Figure(move: 'swing'),
          Figure(move: 'allemande'),
          Figure(move: 'swing'),
        ],
      );
      await dance('one-swing', figures: [Figure(move: 'swing')]);
      await dance(
        'english',
        form: DanceForm.ecd,
        shape: FormationShape.longways,
        figures: [
          Figure(move: 'swing'),
          Figure(move: 'swing'),
        ],
      );
      await program(
        'p',
        slots: [slot('two-swings'), slot('two-swings'), slot('english')],
      );

      final stats = await repertoire.load(const RepertoireScope());
      RepertoireFigureCount of(DanceForm form, String move) =>
          stats.figures.singleWhere((f) => f.form == form && f.move == move);

      expect(of(DanceForm.contra, 'swing').danceCount, 2);
      expect(of(DanceForm.contra, 'swing').callCount, 2);
      expect(of(DanceForm.contra, 'allemande').danceCount, 1);
      expect(of(DanceForm.ecd, 'swing').danceCount, 1);
      expect(of(DanceForm.ecd, 'swing').callCount, 1);
      expect(stats.danceCountsByForm, {DanceForm.contra: 2, DanceForm.ecd: 1});

      // The drill-down filter lists exactly the dances the number counts.
      expect(
        await search(
          AndFilter([
            const FormFilter(DanceForm.contra),
            FigureFilter(FigureLeaf('swing')),
          ]),
        ),
        hasLength(of(DanceForm.contra, 'swing').danceCount),
      );

      final contraOnly = await repertoire.load(
        const RepertoireScope(form: DanceForm.contra),
      );
      expect(contraOnly.figures.map((f) => f.form).toSet(), {DanceForm.contra});
      expect(contraOnly.formsPresent, {DanceForm.contra, DanceForm.ecd});
      expect(contraOnly.danceCount, 2);
    });

    test('most and least called never repeat a dance', () async {
      for (var i = 0; i < 12; i++) {
        await dance('d$i');
      }
      await program(
        'p',
        slots: [
          for (var i = 0; i < 12; i++)
            for (var n = 0; n <= i; n++) slot('d$i'),
        ],
      );
      final stats = await repertoire.load(const RepertoireScope());
      expect(stats.mostCalled.map((d) => d.danceId).take(2), ['d11', 'd10']);
      expect(stats.mostCalled, hasLength(10));
      expect(stats.leastCalled.map((d) => d.danceId), ['d0', 'd1']);
      expect(stats.totalCalls, 78);
    });

    test('authors, formations and venue repeats', () async {
      await choreographers('Kaynor', 'Dart');
      await dance('k1', authors: ['kaynor']);
      await dance(
        'kd',
        authors: ['kaynor', 'dart'],
        shape: FormationShape.becketCw,
      );
      await VenueRepository(db).upsert(Venue(id: 'hall', name: 'Hall'));
      await program(
        'p1',
        venueId: 'hall',
        venue: 'Hall',
        eventDate: DateTime.utc(2026, 9, 1),
        slots: [slot('k1'), slot('k1'), slot('kd')],
      );
      await program(
        'p2',
        venue: 'Grange  Hall',
        eventDate: DateTime.utc(2026, 10, 1),
        slots: [slot('kd')],
      );
      await program(
        'p3',
        venue: 'grange hall',
        eventDate: DateTime.utc(2026, 10, 8),
        slots: [slot('kd')],
      );

      final stats = await repertoire.load(const RepertoireScope());
      expect(stats.authorCount, 2);
      expect(
        [for (final a in stats.authors) (a.name, a.callCount)],
        [('Kaynor', 5), ('Dart', 3)],
      );
      expect(
        [for (final f in stats.formations) (f.shape, f.callCount)],
        [(FormationShape.becketCw, 3), (FormationShape.dupleImproper, 2)],
      );
      expect(stats.venues.map((v) => v.key), [
        VenueKey.typed('grange hall'),
        VenueKey.record('hall'),
      ]);
      expect(stats.venues.first.latestVenueText, 'grange hall');
      expect(
        [for (final v in stats.venues) v.repeats.map((d) => d.danceId)],
        [
          ['kd'],
          ['k1'],
        ],
      );

      // Each drill-down lists the dances behind its row.
      expect(
        await search(
          AndFilter([
            const AuthorFilter('dart'),
            const CalledFilter(called: true),
          ]),
        ),
        {'kd'},
      );
      expect(
        await search(
          AndFilter([
            const FormationFilter(FormationShape.becketCw),
            const CalledFilter(called: true),
          ]),
        ),
        {'kd'},
      );
      expect(
        await search(
          CalledFilter(called: true, venue: VenueKey.typed('grange hall')),
        ),
        {'kd'},
      );
    });
  });

  group('cost', () {
    late QueryCounter counter;

    void openCounted() {
      counter = QueryCounter();
      open(
        CompendiumDatabase(
          NativeDatabase.memory(
            setup: applyCompendiumSqliteSetup,
          ).interceptWith(counter),
        ),
      );
    }

    Future<int> queriesFor(int programCount) async {
      await dance('x');
      await dance('y');
      for (var i = 0; i < programCount; i++) {
        await program(
          'p$i',
          venue: 'Venue ${i % 7}',
          eventDate: DateTime.utc(2026, 1, 1).add(Duration(days: i % 300)),
          slots: [slot('x'), slot(i.isEven ? 'x' : 'y')],
        );
      }
      counter.reset();
      await repertoire.load(RepertoireScope(since: cutoff));
      return counter.count;
    }

    test('the number of queries does not grow with the programs', () async {
      openCounted();
      final few = await queriesFor(10);
      await db.close();
      openCounted();
      final many = await queriesFor(500);
      expect(few, greaterThan(0));
      expect(many, few);
    });
  });
}
