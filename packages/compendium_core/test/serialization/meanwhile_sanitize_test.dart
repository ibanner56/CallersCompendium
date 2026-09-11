import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The archive/.ccshare import path treats `meanwhile` sub-figures as untrusted
/// recursive structure (#590): the decode-time sanitizer must recurse into every
/// nested side (scrubbing control/bidi/format-spoofing free text, #444) and
/// enforce the structural caps defensively — parse-never-fails.
void main() {
  Map<String, Object?> archiveWith(Map<String, Object?> meanwhileFigure) => {
    'schemaVersion': archiveSchemaVersion,
    'exportedAt': '2026-01-01T00:00:00.000Z',
    'dances': [
      {
        'id': 'd1',
        'title': 'Meanwhile Test',
        'authorIds': <String>[],
        'phraseStructure': '',
        'hook': 'hook',
        'callingNotes': 'notes',
        'figures': [meanwhileFigure],
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      },
    ],
  };

  test('recurses sanitization into nested sub-figures', () {
    final archive = archiveWith({
      'move': meanwhileMove,
      'params': {
        'beats': 8,
        'figures': [
          {
            'move': 'custom',
            'params': {'text': 'balance \u202Eand swing'},
            'note': 'no\u0007te',
          },
          {'move': 'orbit', 'note': 'or\u200Bbit'},
        ],
      },
    });

    final result = decodeArchive(jsonEncode(archive));
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

    final container = result.archive.dances.single.figures.single;
    expect(container.isMeanwhile, isTrue);
    final sides = container.subFigures;
    // Control/bidi/format-spoofing characters are stripped at depth, exactly
    // like the one-level #444 scrub.
    expect(sides[0].params['text'], 'balance and swing');
    expect(sides[0].note, 'note');
    expect(sides[1].note, 'orbit');
    for (final side in sides) {
      expect(containsDisallowedText(side.note ?? ''), isFalse);
      final text = side.params['text'];
      if (text is String) expect(containsDisallowedText(text), isFalse);
    }
  });

  test('recurses sanitization into modifier sub-figures', () {
    final archive = archiveWith({
      'move': modifierMove,
      'params': {
        'beats': 16,
        'figures': [
          {'move': 'swing', 'note': 'core\u0007note'},
          {
            'move': customMove,
            'params': {'text': 'turn \u202Eand swing'},
            'note': 'nested\u200Bnote',
          },
        ],
      },
    });

    final result = decodeArchive(jsonEncode(archive));
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

    final container = result.archive.dances.single.figures.single;
    expect(container.isModifier, isTrue);
    expect(container.subFigures[0].note, 'corenote');
    expect(container.subFigures[1].params['text'], 'turn and swing');
    expect(container.subFigures[1].note, 'nestednote');
    for (final child in container.subFigures) {
      expect(containsDisallowedText(child.note ?? ''), isFalse);
      final text = child.params['text'];
      if (text is String) expect(containsDisallowedText(text), isFalse);
    }
  });

  test('drops malformed nested children without dropping the dance', () {
    final archive = archiveWith({
      'move': modifierMove,
      'params': {
        'beats': 16,
        'figures': [
          {'move': 'swing'},
          {'move': 'swing', 'params': <Object?>[]},
          {
            'move': customMove,
            'params': {'text': 'turn'},
          },
        ],
      },
    });

    final result = decodeArchive(jsonEncode(archive));
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    expect(result.archive.dances, hasLength(1));
    expect(
      result.archive.dances.single.figures.single.subFigures.map(
        (figure) => figure.move,
      ),
      ['swing', customMove],
    );
  });

  test('clamps a hostile oversized side count without failing the import', () {
    final sides = [
      for (var i = 0; i < kMaxMeanwhileSides + 20; i++)
        {
          'move': 'custom',
          'params': {'text': 'side $i'},
        },
    ];
    final result = decodeArchive(
      jsonEncode(
        archiveWith({
          'move': meanwhileMove,
          'params': {'beats': 8, 'figures': sides},
        }),
      ),
    );
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    expect(
      result.archive.dances.single.figures.single.subFigures,
      hasLength(kMaxMeanwhileSides),
    );
  });

  test('does not rewrite a `figures` param on a non-meanwhile figure', () {
    // `figures` is only a reserved structural key for the meanwhile container.
    // The sanitizer must scope its recursion/clamp to move == meanwhileMove so
    // a different move (or external data) that happens to use a `figures` param
    // for another purpose is preserved verbatim, not clamped to the side cap or
    // scrubbed to [] (#590 review, thread 1).
    final passengers = [
      for (var i = 0; i < kMaxMeanwhileSides + 5; i++) {'seat': i},
    ];
    final archive = archiveWith({
      'move': 'custom',
      'params': {'text': 'ride', 'figures': passengers},
    });

    final result = decodeArchive(jsonEncode(archive));
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

    final figure = result.archive.dances.single.figures.single;
    expect(figure.isMeanwhile, isFalse);
    final preserved = figure.params['figures'];
    expect(preserved, isA<List<Object?>>());
    // Untouched: neither clamped to the side cap nor emptied.
    expect((preserved as List).length, kMaxMeanwhileSides + 5);
  });

  test('a deeply-nested container is bounded, not stack-overflowing', () {
    // Build meanwhile nested inside meanwhile far past the depth cap.
    Map<String, Object?> nest(int depth) {
      if (depth == 0) {
        return {
          'move': 'custom',
          'params': {'text': 'leaf'},
        };
      }
      return {
        'move': meanwhileMove,
        'params': {
          'beats': 8,
          'figures': [nest(depth - 1)],
        },
      };
    }

    final result = decodeArchive(jsonEncode(archiveWith(nest(200))));
    // The import survives (clamped/flattened at the caps) rather than throwing.
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    final container = result.archive.dances.single.figures.single;
    expect(container.isMeanwhile, isTrue);
    // No meanwhile survives nested inside the decoded container (flat only).
    expect(container.subFigures.every((f) => !f.isMeanwhile), isTrue);
  });
}
