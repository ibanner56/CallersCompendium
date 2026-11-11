import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Leads/Follows lines read back from the app's own display wording (#2121):
/// free-text entry tries the dialect's role words when the line as typed reads
/// a move but not the whole line, and takes that reading only if it reads all
/// of it.
void main() {
  Figure only(String line, {bool withDialect = true}) {
    final figures = parseFreeTextFigureEntry(
      line,
      dialect: withDialect ? Dialect.leadsFollows : null,
    );
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  test('a move read as typed with the role words left as a note', () {
    final f = only('half poussette - leads pull neighbor back then left');
    expect(f.move, 'poussette');
    expect(f.params, {
      'fraction': 'half',
      'who': 'role1s',
      'whom': 'neighbors',
      'direction': 'clockwise',
    });
    expect(f.note, isNull);
  });

  test('a line read as typed into unread parts', () {
    final f = only(
      'leads dance out while follows dance in to a long wave in the center '
      '- balance the wave',
    );
    expect(f.move, 'form_a_long_wave');
    expect(f.params['who'], 'role2s');
    expect(f.params['out'], isTrue);
  });

  test('a role-word reading that leaves a note does not replace one', () {
    // Both readings find the poussette and keep a note, so the line keeps the
    // reading of the words as typed.
    final f = only(
      'half poussette - leads pull neighbor back then left gently',
    );
    expect(f.move, 'poussette');
    expect(f.params, {'fraction': 'half'});
    expect(f.note, contains('leads pull neighbor'));
  });

  test('a role-word reading with a part still unread does not replace one', () {
    // As typed, the swing is read and the second half is not. The role-word
    // reading reads no more of the line, so the unread half keeps the words
    // as typed.
    final f = only('ones swing while follows do a little jig');
    expect(f.isContainer, isTrue);
    expect(f.subFigures.first.params['who'], 'ones');
    expect(f.subFigures.last.isCustom, isTrue);
    expect(f.subFigures.last.params['text'], contains('follows'));
  });

  test('a line whose parts are all unread as typed takes the role words', () {
    // As typed, both halves of the meanwhile are unread, which is a miss, so
    // the role-word reading that reads the swing is taken.
    final f = only('leads swing while follows do a little jig');
    expect(f.isContainer, isTrue);
    expect(f.subFigures.first.move, 'swing');
    expect(f.subFigures.first.params['who'], 'role1s');
  });

  test('with no dialect, the role words are not applied', () {
    final f = only(
      'half poussette - leads pull neighbor back then left',
      withDialect: false,
    );
    expect(f.params, {'fraction': 'half'});
    expect(f.note, isNotNull);
  });
}
