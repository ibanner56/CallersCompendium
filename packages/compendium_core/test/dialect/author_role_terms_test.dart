import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final leadsFollows = Dialect.leadsFollows;
  final gendered = Dialect(
    name: 'Gendered',
    roles: const {'role1': RoleTerm('Gent'), 'role2': RoleTerm('Lady')},
    moves: const {'do_si_do': 'dosido'},
    dancers: const {'onesRole1': 'first gent', 'neighbors': 'the others'},
    discouragedTerms: const ['gypsy', 'larks', 'robin'],
  );

  bool requires(String title, List<String> authorNames) =>
      requiresLarksRobins(title: title, authorNames: authorNames);

  group('requiresLarksRobins', () {
    test('any dance by Rachel or Rae Fifer, however the name is written', () {
      for (final name in [
        'Rachel Fifer',
        'Rae Fifer',
        'rae fifer',
        '  RACHEL   FIFER ',
        'Rachel (Rae) Fifer',
        'Rae "Rachel" Fifer',
      ]) {
        expect(requires('Any Dance At All', [name]), isTrue, reason: name);
      }
    });

    test('a co-written dance', () {
      expect(requires('Some Dance', ['Someone Else', 'Rae Fifer']), isTrue);
    });

    test('not other choreographers, nor a lone family or given name', () {
      for (final name in [
        'Rachel Smith',
        'Bob Fifer',
        'Fifer',
        'Rae',
        'Rachel Fiferson',
      ]) {
        expect(requires('Any Dance At All', [name]), isFalse, reason: name);
      }
    });

    test('the two named dances when no author is named', () {
      for (final title in [
        'Renewed Joy',
        'renewed  joy',
        "If I Was Dead and It Wouldn't Go To Waste",
        'If I Was Dead and It Wouldn’t Go to Waste',
      ]) {
        expect(requires(title, const []), isTrue, reason: title);
        expect(requires(title, const ['Unknown']), isTrue, reason: title);
        expect(requires(title, const ['Traditional']), isTrue, reason: title);
      }
    });

    test('not a same-titled dance by someone else', () {
      expect(requires('Renewed Joy', const ['Someone Else']), isFalse);
    });

    test('not other titles with no author', () {
      expect(requires('Renewed Joy Reel', const []), isFalse);
      expect(requires('Petronella', const []), isFalse);
    });
  });

  group('dialectForDance', () {
    test('calls the roles lark and robin and keeps the rest', () {
      final shown = dialectForDance(
        gendered,
        title: 'Renewed Joy',
        authorNames: const ['Rachel Fifer'],
      );
      expect(shown.roles, {
        'role1': const RoleTerm('lark'),
        'role2': const RoleTerm('robin'),
      });
      expect(shown.name, gendered.name);
      expect(shown.moves, gendered.moves);
      expect(shown.validate(), isEmpty);
    });

    test('drops single-dancer words, keeps the other dancer words', () {
      final shown = dialectForDance(
        gendered,
        title: 'x',
        authorNames: const ['Rae Fifer'],
      );
      expect(shown.dancers, {'neighbors': 'the others'});
      expect(
        FigureRenderer.singleDancerDefaultTerm('onesRole1', shown),
        'first lark',
      );
    });

    test('stops flagging lark and robin as discouraged', () {
      final shown = dialectForDance(
        gendered,
        title: 'x',
        authorNames: const ['Rae Fifer'],
      );
      expect(shown.discouragedTerms, ['gypsy']);
    });

    test('returns the dialect itself for any other dance', () {
      final shown = dialectForDance(
        leadsFollows,
        title: 'Petronella',
        authorNames: const ['Someone Else'],
      );
      expect(shown, same(leadsFollows));
      expect(
        overridesRoleTerms(
          leadsFollows,
          title: 'Petronella',
          authorNames: const ['Someone Else'],
        ),
        isFalse,
      );
    });

    test('returns the dialect itself when it already says lark and robin', () {
      final capitalised = Dialect(
        name: 'Mine',
        roles: const {'role1': RoleTerm('Lark'), 'role2': RoleTerm('Robin')},
        dancers: const {'onesRole1': 'lark one'},
      );
      for (final dialect in [Dialect.larksRobins, capitalised]) {
        expect(
          dialectForDance(
            dialect,
            title: 'x',
            authorNames: const ['Rae Fifer'],
          ),
          same(dialect),
        );
        expect(
          overridesRoleTerms(
            dialect,
            title: 'x',
            authorNames: const ['Rae Fifer'],
          ),
          isFalse,
        );
      }
    });

    test('overrides the canonical dialect, which names no role terms', () {
      expect(
        overridesRoleTerms(
          Dialect.canonical,
          title: 'x',
          authorNames: const ['Rae Fifer'],
        ),
        isTrue,
      );
    });
  });

  group('exports', () {
    final now = DateTime.utc(2026, 11, 19);
    final dance = Dance(
      id: 'd1',
      title: 'Renewed Joy',
      figures: [
        Figure(move: 'allemande', params: const {'who': 'role1s'}),
        Figure(move: 'orbit', params: const {'who': 'role2s'}),
      ],
      callingNotes: 'role1s start on the left',
      createdAt: now,
      updatedAt: now,
    );

    String text(List<String> authorNames, {Set<DanceShareField>? fields}) =>
        danceToPlainText(
          dance,
          dialect: leadsFollows,
          authorNames: authorNames,
          formationLabel: 'Duple improper',
          statusLabel: 'Active',
          fields: fields ?? DanceShareField.allExceptTunes,
        ).toLowerCase();

    test('a dance by Rachel Fifer exports with larks and robins', () {
      final exported = text(const ['Rachel Fifer']);
      expect(exported, contains('lark'));
      expect(exported, contains('robin'));
      expect(exported, isNot(contains('lead')));
      expect(exported, isNot(contains('follow')));
    });

    test('even with the authors left off the card', () {
      final exported = text(
        const ['Rachel Fifer'],
        fields: {...DanceShareField.allExceptTunes}
          ..remove(DanceShareField.authors),
      );
      expect(exported, isNot(contains('fifer')));
      expect(exported, contains('lark'));
      expect(exported, isNot(contains('lead')));
    });

    test("another choreographer's dance keeps the reader's dialect", () {
      final exported = text(const ['Someone Else']);
      expect(exported, contains('lead'));
      expect(exported, isNot(contains('lark')));
    });

    test('the card carries the dialect it was rendered in', () {
      final content = DanceCardContent.build(
        dance,
        dialect: leadsFollows,
        authorNames: const ['Rae Fifer'],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
      );
      expect(content.dialect.roles['role1'], const RoleTerm('lark'));
      expect(content.callingNotes, 'larks start on the left');
    });
  });
}
