import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The remaining moves read back from the app's own display wording (#2121);
/// the round-trip ratchet covers each value alone, these pin whole figures and
/// the lines the readers refuse.
void main() {
  Figure only(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  Figure imported(String line) {
    final figures = parseFigureLinesFanOut(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  group('poussette', () {
    test('reads the fraction, both pairs and the turn', () {
      expect(
        only(
          'three quarter poussette - shadows pull opposites back then right',
        ).params,
        {
          'fraction': 'threeQuarter',
          'who': 'shadows',
          'whom': 'opposites',
          'direction': 'counterclockwise',
        },
      );
    });

    test('back then left is clockwise, as ContraDB writes it', () {
      expect(
        only(
          'half poussette - role1s pull neighbor back then left',
        ).params['direction'],
        'clockwise',
      );
    });
  });

  group('zig-zag', () {
    test('reads the pair and the ender', () {
      expect(
        only(
          'zig right zag left with neighbor, trailing two catching hands',
        ).params,
        {'slide': 'right', 'who': 'neighbors', 'ender': 'allemande'},
      );
      expect(only('zig left zag right with partner into a ring').params, {
        'slide': 'left',
        'who': 'partners',
        'ender': 'ring',
      });
    });

    test('a zag that is not the mirror of the zig is not this wording', () {
      expect(only('zig left zag left with partner').params['who'], isNull);
    });
  });

  group('figure 8', () {
    test('reads the fraction, the direction and who leads', () {
      expect(
        only(
          'twos three quarter figure 8 down between ones, first lark '
          'leading',
        ).params,
        {
          'who': 'twos',
          'fraction': 'threeQuarter',
          'where': 'below',
          'lead': 'onesRole1',
        },
      );
    });

    test('a figure 8 with no direction is left to the existing readers', () {
      // The display writes it for `where: none`; ContraDB's meaning is not
      // established, so it is not read as none.
      expect(only('ones half figure 8').params['where'], isNot('none'));
    });
  });

  test('a box circulate reads the display\'s subjects and its others', () {
    expect(
      only(
        'balance & box circulate - partners cross while others loop left',
      ).params,
      {'balance': true, 'who': 'partners', 'hand': 'left'},
    );
  });

  group('swing', () {
    test('reads the displayed ending facing', () {
      expect(only('partner balance & swing, end facing up the hall').params, {
        'who': 'partners',
        'prefix': 'balance',
        'endFacing': 'up',
      });
      expect(only('neighbor swing, end facing along the set').params, {
        'who': 'neighbors',
        'endFacing': 'along',
      });
    });

    test('a facing with more after it is not this wording', () {
      final f = only('partner swing, end facing up the hall gently');
      expect(f.params['endFacing'], isNot('up'));
    });
  });

  test('a promenade reads its displayed direction', () {
    for (final (line, where) in [
      ('partner promenade on left diagonal', 'leftDiagonal'),
      ('partner promenade facing down', 'down'),
      ('partner promenade across', 'across'),
    ]) {
      final f = only(line);
      expect(f.move, 'promenade', reason: line);
      expect(f.params['where'], where, reason: line);
      expect(f.note, isNull, reason: line);
    }
  });

  test('a promenade reads a displayed direction before its turn', () {
    final f = only('partners promenade on left diagonal on the left');
    expect(f.params, {
      'who': 'partners',
      'where': 'leftDiagonal',
      'direction': 'clockwise',
    });
    expect(f.note, isNull);
  });

  test('a revolving door reads the display\'s subjects', () {
    expect(
      only(
        'revolving door - third corners take right hands and drop off '
        'neighbor on other side',
      ).params,
      {'who': 'thirdCorners', 'hand': 'right', 'whom': 'neighbors'},
    );
  });

  test('a take without the give reads its displayed partner', () {
    expect(only('role1s take partner').params, {
      'who': 'role1s',
      'whom': 'partners',
      'give': false,
    });
  });

  group('halls', () {
    test('read a displayed subject and forward then backward', () {
      final who = only('third corners down the hall and turn as a couple');
      expect(who.params['who'], 'thirdCorners');
      expect(who.params['ender'], 'turnCouple');
      final facing = only(
        'up the hall forward then backward and bend into a ring',
      );
      expect(facing.params['facing'], 'forwardThenBackward');
      expect(facing.params['ender'], 'circle');
      expect(facing.note, isNull);
    });

    test('bend the line is still left as a note', () {
      // ContraDB's own test pins this phrase as a note; reading it is a scope
      // decision this batch does not take.
      final f = only('down the hall and bend the line');
      expect(f.params['ender'], isNot('bendTheLine'));
    });
  });

  test('a single file circle reads as one', () {
    expect(only('single file circle left 3 places').params, {
      'direction': 'left',
      'singleFile': true,
      'places': 3,
    });
  });

  test('a facing star reads counterclockwise and the display\'s subjects', () {
    final f = only(
      'facing star counterclockwise 3 places with third corners putting '
      'their right hands in and backing up',
    );
    expect(f.params['direction'], 'counterclockwise');
    expect(f.params['who'], 'thirdCorners');
    expect(f.note, isNull);
  });

  group('an import keeps the readers\' looser lines as before', () {
    test('a take naming one partner, with more after it, is not read', () {
      for (final line in [
        'gentlespoons take partner in ballroom position',
        'role1s take partner by the right hand',
      ]) {
        expect(imported(line).isCustom, isTrue, reason: line);
      }
    });

    test('a figure 8 led by a pair is left to ContraDB\'s reader', () {
      final f = imported('ones half figure 8 across, partners leading');
      expect(f.move, 'figure_8');
      expect(f.params['where'], 'across');
      expect(f.params.containsKey('lead'), isFalse);
    });

    test('a figure 8 between its own dancers is not the display\'s', () {
      expect(
        imported('ones half figure 8 up between ones').params['where'],
        isNot('above'),
      );
    });

    test('a facing phrase that goes on is not split into a direction', () {
      for (final line in [
        'partners promenade facing up the hall',
        'pass through facing up the hall',
      ]) {
        final f = imported(line);
        expect(f.params.containsKey('where'), isFalse, reason: line);
        expect(f.note, contains('facing up the hall'), reason: line);
      }
    });

    test('a promenade direction before its destination is still read', () {
      final f = imported('centers promenade facing down to first lead');
      expect(f.params['where'], 'down');
    });
  });
}
