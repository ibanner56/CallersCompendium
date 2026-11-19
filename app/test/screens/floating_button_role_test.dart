import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The floating button means one thing: create, on a list
/// (`docs/design/ux.md`, "Where Save, New and the record's name go"). Save
/// lives in an editor's top bar and Edit in a record's, so a floating button
/// whose icon is not the "+" is one of those creeping back. Every screen that
/// floats one also leaves [AppSpacing.fabClearance] below its list, so the
/// button never covers the last row.
final _fab = RegExp(r'\bFloatingActionButton(?:\.\w+)?\(');
final _addIcon = RegExp(r'\bIcons\.add\b');

/// The argument list of the call whose `(` is at [open] in [source], walking
/// the delimiters and skipping string literals.
String _callAt(String source, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  throw StateError('unbalanced call at $open');
}

/// `path:line` for each floating button in [source] that is not a create.
List<String> nonCreateFabsIn(String path, String source) => [
  for (final match in _fab.allMatches(source))
    if (!_addIcon.hasMatch(_callAt(source, match.end - 1)))
      '$path:${'\n'.allMatches(source.substring(0, match.start)).length + 1}',
];

/// Whether [source] floats a button at all.
bool floatsAButton(String source) => _fab.hasMatch(source);

void main() {
  final files = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('every floating button in the app creates', () {
    expect(files, isNotEmpty, reason: 'run from the app/ directory');
    final floating = [
      for (final f in files)
        if (floatsAButton(f.readAsStringSync())) f.path,
    ];
    // Positive control: the list screens do float New. If none is found,
    // the scan is not looking at the app.
    expect(floating.length, greaterThanOrEqualTo(4));
    expect(
      [for (final f in files) ...nonCreateFabsIn(f.path, f.readAsStringSync())],
      isEmpty,
      reason:
          'the floating button is for creating on a list; Save and Edit go '
          'in the top bar',
    );
  });

  test('every screen that floats a button leaves room for it', () {
    expect(
      [
        for (final f in files)
          if (floatsAButton(f.readAsStringSync()) &&
              !f.readAsStringSync().contains('AppSpacing.fabClearance'))
            f.path,
      ],
      isEmpty,
      reason:
          'pad the list with AppSpacing.fabClearance so the button never '
          'covers its last row',
    );
  });

  test('the scanner flags Save and Edit buttons, not New', () {
    const save = '''
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('save'),
        onPressed: () => _save('(not a paren'),
        icon: const Icon(Icons.save_outlined),
        label: Text(l10n.commonSave),
      ),''';
    const edit = 'FloatingActionButton(child: Icon(Icons.add_circle))';
    const create = '''
      FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.venueNew),
      )''';
    expect(nonCreateFabsIn('x.dart', save), ['x.dart:1']);
    expect(nonCreateFabsIn('x.dart', edit), hasLength(1));
    expect(nonCreateFabsIn('x.dart', create), isEmpty);
    expect(floatsAButton('FloatingActionButtonThemeData()'), isFalse);
  });
}
