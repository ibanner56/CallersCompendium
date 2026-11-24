import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('splitPhraseLabel', () {
    test('splits A1..C2 with or without a closing mark', () {
      expect(splitPhraseLabel('A1 (8) neighbor balance'), (
        'A1',
        '(8) neighbor balance',
      ));
      expect(splitPhraseLabel('b2: swing'), ('B2', 'swing'));
      expect(splitPhraseLabel('C1) circle left'), ('C1', 'circle left'));
      expect(splitPhraseLabel('A2. long lines'), ('A2', 'long lines'));
      expect(splitPhraseLabel('B1- hey'), ('B1', 'hey'));
      expect(splitPhraseLabel('A1'), ('A1', ''));
    });

    test('leaves a line without a label as it is', () {
      expect(splitPhraseLabel('A12 swing'), (null, 'A12 swing'));
      expect(splitPhraseLabel('B1s cross'), (null, 'B1s cross'));
      expect(splitPhraseLabel('D1 swing'), (null, 'D1 swing'));
      expect(splitPhraseLabel('(8) swing'), (null, '(8) swing'));
    });
  });

  group('splitFigureTextLines', () {
    List<String> texts(FigureTextLines result) => [
      for (final line in result.lines) line.text,
    ];

    test('reads one figure line per non-empty line, trimmed', () {
      final result = splitFigureTextLines(
        '  (8) neighbor balance & swing\n\n'
        '(8) long lines\r\n'
        '\t(8) ladies chain\r'
        '(8) half hey\u2028(8) partner swing\n   \n',
        dropPhraseLabels: false,
      );
      expect(result.refusal, isNull);
      expect(texts(result), [
        '(8) neighbor balance & swing',
        '(8) long lines',
        '(8) ladies chain',
        '(8) half hey',
        '(8) partner swing',
      ]);
    });

    test('drops a leading phrase label when asked, and label-only lines', () {
      final result = splitFigureTextLines(
        'A1 (8) Neighbor balance & swing\n'
        'B1\n'
        'b2: (8) partner swing\n'
        '(8) long lines',
        dropPhraseLabels: true,
      );
      expect(result.lines, const [
        FigureTextLine(text: '(8) Neighbor balance & swing', label: 'A1'),
        FigureTextLine(text: '(8) partner swing', label: 'B2'),
        FigureTextLine(text: '(8) long lines'),
      ]);
    });

    test('keeps the label when not asked to drop it (English), but skips a '
        'label-only line', () {
      final result = splitFigureTextLines(
        'A1\nA1 1-8 lead up\nB1:',
        dropPhraseLabels: false,
      );
      expect(result.lines, const [FigureTextLine(text: 'A1 1-8 lead up')]);
    });

    test('empty text reads no lines and is not refused', () {
      final result = splitFigureTextLines(' \n\n ', dropPhraseLabels: true);
      expect(result.lines, isEmpty);
      expect(result.refusal, isNull);
    });

    test('refuses whole text over the line cap', () {
      final atCap = List.filled(maxFigureTextLines, 'swing').join('\n');
      expect(
        splitFigureTextLines(atCap, dropPhraseLabels: false).lines,
        hasLength(maxFigureTextLines),
      );
      // Blank lines do not count toward the cap.
      expect(
        splitFigureTextLines('$atCap\n\n  \n', dropPhraseLabels: false).refusal,
        isNull,
      );
      final over = splitFigureTextLines(
        '$atCap\nswing',
        dropPhraseLabels: false,
      );
      expect(over.refusal, FigureTextRefusal.tooManyLines);
      expect(over.lines, isEmpty);
    });

    test('label-only lines do not count toward the line cap', () {
      final atCap = List.filled(maxFigureTextLines, 'swing').join('\n');
      expect(
        splitFigureTextLines('A1\n$atCap\nB2', dropPhraseLabels: true).refusal,
        isNull,
      );
    });

    test('refuses whole text with a line over the parser\'s line cap', () {
      final atCap = 'a' * maxFreeTextEntryLength;
      expect(
        splitFigureTextLines('swing\n$atCap', dropPhraseLabels: false).lines,
        hasLength(2),
      );
      // The label is not counted: the parser never sees it.
      expect(
        splitFigureTextLines('A1 $atCap', dropPhraseLabels: true).refusal,
        isNull,
      );
      final over = splitFigureTextLines(
        'swing\n${atCap}a',
        dropPhraseLabels: false,
      );
      expect(over.refusal, FigureTextRefusal.lineTooLong);
      expect(over.lines, isEmpty);
    });

    test('refuses whole text over the length cap', () {
      // 100 lines of 199 characters and a line break: exactly the cap.
      final atCap = '${List.filled(100, 'a' * 199).join('\n')}\n';
      expect(atCap.length, maxFigureTextLength);
      expect(
        splitFigureTextLines(atCap, dropPhraseLabels: false).refusal,
        isNull,
      );
      final over = splitFigureTextLines('${atCap}a', dropPhraseLabels: false);
      expect(over.refusal, FigureTextRefusal.tooLong);
      expect(over.lines, isEmpty);
    });
  });
}
