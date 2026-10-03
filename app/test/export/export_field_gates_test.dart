import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet (CS-48b): the dance-card field gating lives in core's
/// `DanceCardContent`. The app's export layout must not re-grow its own
/// `DanceShareField.x` gates — the only allowed mention is the
/// `fields = DanceShareField.allExceptTunes` default parameter (and its
/// dartdoc).
final _gate = RegExp(r'DanceShareField\.(?!allExceptTunes\b)\w+');
final _containsGate = RegExp(r'\bfields\.contains\(');

/// `path:line: text` for each gate-shaped line in [source].
List<String> fieldGatesIn(String path, String source) => [
  for (final (i, line) in source.split('\n').indexed)
    if (_gate.hasMatch(line) || _containsGate.hasMatch(line))
      '$path:${i + 1}: ${line.trim()}',
];

void main() {
  test('app/lib/src/export has no DanceShareField gates', () {
    final files = Directory('lib/src/export')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'run from the app/ directory');

    final gates = [
      for (final f in files) ...fieldGatesIn(f.path, f.readAsStringSync()),
    ];
    expect(
      gates,
      isEmpty,
      reason:
          'gate dance-card fields in core DanceCardContent, not in the PDF '
          'layout',
    );
  });

  test('the scanner flags a gate but not the default parameter', () {
    expect(
      fieldGatesIn('x.dart', 'fields.contains(DanceShareField.callingNotes)'),
      hasLength(1),
    );
    expect(
      fieldGatesIn(
        'x.dart',
        'Set<DanceShareField> fields = DanceShareField.allExceptTunes,',
      ),
      isEmpty,
    );
    expect(
      fieldGatesIn('x.dart', 'if (f == DanceShareField.allExceptTunesX)'),
      hasLength(1),
    );
  });
}
