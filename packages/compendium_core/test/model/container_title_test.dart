import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The optional title of a structural container: stored normalized under
/// `params['title']`, carried through the codec, and tolerant of untrusted
/// input (clamped, never rejected).
void main() {
  final a = Figure(move: 'balance', params: const {'who': 'partners'});
  final b = Figure(move: 'swing', params: const {'who': 'partners'});

  group('normalizeContainerTitle', () {
    test('trims and collapses whitespace, line breaks included', () {
      expect(normalizeContainerTitle('  Flutter\n\twheel  '), 'Flutter wheel');
    });

    test('a blank or non-string title is no title', () {
      expect(normalizeContainerTitle(''), isNull);
      expect(normalizeContainerTitle(' \n '), isNull);
      expect(normalizeContainerTitle(null), isNull);
      expect(normalizeContainerTitle(42), isNull);
      expect(normalizeContainerTitle(const ['x']), isNull);
    });

    test('clamps to the cap', () {
      final long = 'x' * (kMaxContainerTitleLength + 20);
      expect(normalizeContainerTitle(long), 'x' * kMaxContainerTitleLength);
    });

    test('never splits a surrogate pair at the cap', () {
      // 79 ASCII letters then an emoji (two code units) straddling the cap.
      final raw = '${'x' * (kMaxContainerTitleLength - 1)}\u{1F483}tail';
      final clamped = normalizeContainerTitle(raw)!;
      expect(clamped, 'x' * (kMaxContainerTitleLength - 1));
      expect(clamped.length, lessThanOrEqualTo(kMaxContainerTitleLength));
    });
  });

  group('the container factories', () {
    test('store a title under params["title"], normalized', () {
      final f = Figure.sequence(
        figures: [a, b],
        beats: 16,
        title: '  Balance\nand swing ',
      );
      expect(f.params[containerTitleKey], 'Balance and swing');
      expect(f.containerTitle, 'Balance and swing');
    });

    test('leave the key out when there is no title, so an untitled '
        'container is exactly what it was before titles existed', () {
      for (final title in [null, '', '   ']) {
        final f = Figure.meanwhile(figures: [a, b], beats: 8, title: title);
        expect(f.params.containsKey(containerTitleKey), isFalse);
        expect(f, Figure.meanwhile(figures: [a, b], beats: 8));
      }
    });

    test('take a title from extraParams, as the editor passes it', () {
      final f = Figure.modifier(
        figures: [a, b],
        beats: 8,
        extraParams: const {containerTitleKey: ' Named '},
      );
      expect(f.containerTitle, 'Named');
      expect(f.params[containerTitleKey], 'Named');
    });

    test('an explicit title wins over one in extraParams', () {
      final f = Figure.modifier(
        figures: [a, b],
        beats: 8,
        extraParams: const {containerTitleKey: 'Old'},
        title: 'New',
      );
      expect(f.containerTitle, 'New');
    });

    test('drop a non-string title from extraParams rather than store it', () {
      final f = Figure.sequence(
        figures: [a, b],
        beats: 8,
        extraParams: const {containerTitleKey: 7},
      );
      expect(f.params.containsKey(containerTitleKey), isFalse);
    });
  });

  group('the figure codec', () {
    test('round-trips a titled container, nested ones included', () {
      final inner = Figure.sequence(
        figures: [a, b],
        beats: 8,
        title: 'Balance and swing',
      );
      final outer = Figure.meanwhile(
        figures: [inner, a],
        beats: 8,
        title: 'Both at once',
      );
      final decoded = decodeFigures(encodeFigures([outer]));
      expect(decoded, [outer]);
      expect(decoded.single.containerTitle, 'Both at once');
      expect(
        decoded.single.subFigures.first.containerTitle,
        'Balance and swing',
      );
    });

    test('writes no title key for an untitled container', () {
      final json = figureToJson(Figure.sequence(figures: [a, b], beats: 8));
      expect((json['params']! as Map).containsKey(containerTitleKey), isFalse);
    });

    test('normalizes an untrusted title on decode, and drops a bad one', () {
      Map<String, Object?> container(Object? title) => {
        'move': sequenceMove,
        'params': {
          'beats': 8,
          'figures': [figureToJson(a), figureToJson(b)],
          containerTitleKey: title,
        },
      };
      expect(
        figureFromJson(container('  Two\r\nlines  ')).params[containerTitleKey],
        'Two lines',
      );
      final long = figureFromJson(container('y' * 500));
      expect(long.containerTitle!.length, kMaxContainerTitleLength);
      for (final bad in [
        null,
        3,
        true,
        const {'x': 1},
        '   ',
      ]) {
        final decoded = figureFromJson(container(bad));
        expect(
          decoded.params.containsKey(containerTitleKey),
          isFalse,
          reason: '$bad',
        );
      }
    });

    test('leaves a "title" param on an ordinary figure alone', () {
      final decoded = figureFromJson({
        'move': 'balance',
        'params': {'who': 'partners', containerTitleKey: 7},
      });
      expect(decoded.params[containerTitleKey], 7);
      expect(decoded.containerTitle, isNull);
    });
  });
}
