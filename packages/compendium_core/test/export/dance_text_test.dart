import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10);
  final larks = Dialect.larksRobins;

  Dance dance({
    String title = 'Rory O\'More',
    List<String> authorIds = const [],
    Formation formation = const Formation(FormationShape.dupleImproper),
    String phraseStructure = '',
    List<Figure> figures = const [],
    String callingNotes = '',
    DanceStatus status = DanceStatus.active,
    DanceLevel? level,
  }) => Dance(
    id: 'd1',
    title: title,
    authorIds: authorIds,
    formation: formation,
    phraseStructure: phraseStructure,
    figures: figures,
    callingNotes: callingNotes,
    status: status,
    level: level,
    createdAt: now,
    updatedAt: now,
  );

  String render(
    Dance d, {
    Dialect? dialect,
    List<String> authorNames = const [],
    String formationLabel = 'Duple improper',
    String? levelLabel,
    String statusLabel = 'Active',
  }) => danceToPlainText(
    d,
    dialect: dialect ?? Dialect.canonical,
    authorNames: authorNames,
    formationLabel: formationLabel,
    levelLabel: levelLabel,
    statusLabel: statusLabel,
  );

  group('danceToPlainText', () {
    test('renders the title as the first line', () {
      final text = render(dance(title: 'Rory O\'More'));
      expect(text.split('\n').first, 'Rory O\'More');
    });

    test('renders resolved author names joined, omitting blanks', () {
      final text = render(
        dance(authorIds: ['a1', 'a2']),
        authorNames: ['Ted Sannella', '  ', 'Cary Ravitz'],
      );
      expect(text, contains('Ted Sannella, Cary Ravitz'));
    });

    test('omits the author line when no names are given', () {
      final text = render(dance());
      final lines = text.split('\n');
      // Line 1 is the title; line 2 should be the Formation, not an author line.
      expect(lines[1], startsWith('Formation:'));
    });

    test('renders formation, level, and status labels', () {
      final text = render(
        dance(status: DanceStatus.broken, level: DanceLevel.intermediate),
        formationLabel: 'Becket',
        levelLabel: 'Intermediate',
        statusLabel: 'Broken',
      );
      expect(text, contains('Formation: Becket'));
      expect(text, contains('Level: Intermediate'));
      expect(text, contains('Status: Broken'));
    });

    test('omits the Level line when levelLabel is null', () {
      final text = render(dance(), levelLabel: null);
      expect(text, isNot(contains('Level:')));
    });

    test('omits the Status line for an active dance', () {
      // Mirrors the detail card, which only banners a non-active status.
      final text = render(dance(status: DanceStatus.active));
      expect(text, isNot(contains('Status:')));
    });

    test('includes the Status line for a non-active dance', () {
      final text = render(
        dance(status: DanceStatus.deprecated),
        statusLabel: 'Deprecated',
      );
      expect(text, contains('Status: Deprecated'));
    });

    test('renders the non-standard phrase structure notation', () {
      final text = render(dance(phraseStructure: '6*8*2'));
      expect(text, contains('Phrase: 6*8*2'));
    });

    test('omits the Phrase line for the standard structure', () {
      final text = render(dance(phraseStructure: ''));
      expect(text, isNot(contains('Phrase:')));
    });

    test('renders figures grouped by derived section with beats', () {
      final text = render(
        dance(
          figures: [
            Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
            Figure(move: 'do_si_do', params: {'who': 'partners', 'beats': 8}),
          ],
        ),
      );
      expect(text, contains('Figures:'));
      // First figure starts at beat 0 → section A1; second at beat 16 → A2.
      expect(text, contains('A1  partners swing (16 beats)'));
      expect(text, contains('A2  partners do si do once (8 beats)'));
    });

    test('marks a progression figure and renders per-figure notes', () {
      final text = render(
        dance(
          figures: [
            Figure(
              move: 'swing',
              params: {'who': 'neighbors', 'beats': 16},
              progression: true,
              note: 'end facing across',
            ),
          ],
        ),
      );
      expect(text, contains('¶'));
      expect(text, contains('    end facing across'));
    });

    test('uses singular "beat" for a one-beat figure', () {
      final text = render(
        dance(
          figures: [
            Figure(move: 'swing', params: {'beats': 1}),
          ],
        ),
      );
      expect(text, contains('(1 beat)'));
      expect(text, isNot(contains('(1 beats)')));
    });

    test('applies the dialect to figure role terms', () {
      final d = dance(
        figures: [
          Figure(move: 'swing', params: {'who': 'role1s', 'beats': 16}),
        ],
      );
      final canonical = render(d, dialect: Dialect.canonical);
      final dialectal = render(d, dialect: larks);

      // Canonical keeps the role token; the dialect substitutes it.
      expect(canonical, contains('role1s swing'));
      expect(canonical, isNot(contains('Larks swing')));
      expect(dialectal, contains('Larks swing'));
      expect(dialectal, isNot(contains('role1s swing')));
    });

    test('applies the dialect to calling notes free text', () {
      final d = dance(callingNotes: 'The role1s lead out.');
      expect(render(d, dialect: Dialect.canonical), contains('role1s lead'));
      expect(render(d, dialect: larks), contains('Larks lead'));
    });

    test('includes a Calling notes section when notes are present', () {
      final text = render(dance(callingNotes: 'Teach the box the gnat first.'));
      expect(text, contains('Calling notes:'));
      expect(text, contains('Teach the box the gnat first.'));
    });

    test('omits the Calling notes section when notes are blank', () {
      final text = render(dance(callingNotes: '   '));
      expect(text, isNot(contains('Calling notes:')));
    });

    test('renders the header only for a figureless, note-less dance', () {
      final text = render(dance(title: 'Stub'));
      expect(text, isNot(contains('Figures:')));
      expect(text, isNot(contains('Calling notes:')));
      expect(text.split('\n').first, 'Stub');
    });

    // Privacy invariant (ROADMAP 4b.4): the shareable card is built solely from
    // the Dance plus caller-resolved *name* strings. No Choreographer record is
    // ever passed in, so private contact fields (email/location) have no path
    // into a shared export. This test locks that API shape: author content comes
    // only from the `authorNames` argument.
    test('renders authors only from the provided names (privacy)', () {
      const email = 'ted@example.com';
      const location = 'Boston, MA';
      final text = render(
        dance(authorIds: ['a1']),
        authorNames: const ['Ted Sannella'],
      );
      expect(text, contains('Ted Sannella'));
      expect(text, isNot(contains(email)));
      expect(text, isNot(contains(location)));
    });
  });
}
