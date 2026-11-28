import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The floating button does one of two jobs (`docs/design/ux.md`, "Where
/// Save, New and the record's name go"): it creates, on a list ("+"), or it
/// opens a record from its read view, as Edit (a pencil) or, on a preview not
/// yet in the collection, Import. It never saves: Save lives in an editor's
/// top bar, so a floating button with any other icon is a floating Save, or a
/// new job, creeping in. Every screen that floats one also leaves
/// [AppSpacing.fabClearance] below its content, so the button never covers
/// the last row.
///
/// Screens float their labelled button through `adaptiveExtendedFab(...)`
/// (`widgets/adaptive_fab.dart`), so a call to it counts as a floating button
/// here, with its own icon argument. The helper itself only forwards its
/// caller's icon and is left out of the scan; its callers are what is checked.
final _fab = RegExp(
  r'\b(?:FloatingActionButton(?:\.\w+)?|adaptiveExtendedFab)\(',
);
const _fabHelper = 'adaptive_fab.dart';
final _allowedIcon = RegExp(
  r'\bIcons\.(?:add|edit_outlined|library_add_outlined)\b',
);

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

/// `path:line` for each floating button in [source] whose icon is not New,
/// Edit or Import.
List<String> strayFabsIn(String path, String source) => [
  for (final match in _fab.allMatches(source))
    if (!_allowedIcon.hasMatch(_callAt(source, match.end - 1)))
      '$path:${'\n'.allMatches(source.substring(0, match.start)).length + 1}',
];

/// Whether [source] floats a button at all.
bool floatsAButton(String source) => _fab.hasMatch(source);

void main() {
  final files = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith(_fabHelper))
      .toList();

  test('every floating button creates, edits or imports; none saves', () {
    expect(files, isNotEmpty, reason: 'run from the app/ directory');
    final floating = [
      for (final f in files)
        if (floatsAButton(f.readAsStringSync())) f.path,
    ];
    // Positive control: the list screens do float New. If none is found,
    // the scan is not looking at the app.
    expect(floating.length, greaterThanOrEqualTo(4));
    expect(
      [for (final f in files) ...strayFabsIn(f.path, f.readAsStringSync())],
      isEmpty,
      reason:
          'the floating button creates on a list or opens a record\'s editor; '
          'Save goes in the editor\'s top bar',
    );
  });

  // A coarse net: it asks only that the file use the token, not that the
  // padding sits on the list under the button. The per-screen
  // `expectFabClearsLastRow` tests check the geometry.
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

  // `docs/design/ux.md`: in a short window (a phone in landscape) each
  // screen's labelled floating button folds to its icon. Only the shared
  // helper does that, so a labelled button built any other way never folds.
  test('every labelled floating button goes through adaptiveExtendedFab', () {
    final extended = RegExp(r'\bFloatingActionButton\.extended\(');
    expect(
      [
        for (final f in files)
          for (final match in extended.allMatches(f.readAsStringSync()))
            '${f.path}:${'\n'.allMatches(f.readAsStringSync().substring(0, match.start)).length + 1}',
      ],
      isEmpty,
      reason:
          'use adaptiveExtendedFab (widgets/adaptive_fab.dart), which folds '
          'the button to its icon in a short window',
    );
    // Positive control: the helper itself builds one, and is what the scan
    // leaves out.
    expect(
      extended.hasMatch(File('lib/src/widgets/$_fabHelper').readAsStringSync()),
      isTrue,
    );
  });

  test('the scanner flags Save and other icons, not New, Edit or Import', () {
    const save = '''
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('save'),
        onPressed: () => _save('(not a paren'),
        icon: const Icon(Icons.save_outlined),
        label: Text(l10n.commonSave),
      ),''';
    const other = 'FloatingActionButton(child: Icon(Icons.add_circle))';
    const create = '''
      FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.venueNew),
      )''';
    const edit = '''
      FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.edit_outlined),
        label: Text(l10n.danceEditFab),
      )''';
    const import =
        'FloatingActionButton.extended('
        'icon: const Icon(Icons.library_add_outlined), onPressed: null)';
    expect(strayFabsIn('x.dart', save), ['x.dart:1']);
    expect(strayFabsIn('x.dart', other), hasLength(1));
    expect(strayFabsIn('x.dart', create), isEmpty);
    expect(strayFabsIn('x.dart', edit), isEmpty);
    expect(strayFabsIn('x.dart', import), isEmpty);
    expect(floatsAButton('FloatingActionButtonThemeData()'), isFalse);
    // A screen's call to the shared helper is a floating button too.
    const helperSave = '''
      adaptiveExtendedFab(
        context,
        key: const ValueKey('save'),
        icon: const Icon(Icons.save_outlined),
        label: l10n.commonSave,
      )''';
    expect(strayFabsIn('x.dart', helperSave), ['x.dart:1']);
    expect(floatsAButton(helperSave), isTrue);
  });
}
