import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_scan.dart';

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

/// Floating buttons whose icon or label changes with the screen's state, each
/// with what it switches between. One that is Save while the form is dirty
/// and New otherwise reads as a floating Save the icon scan cannot see, so a
/// state-dependent floating button is listed here on purpose. Each entry
/// must still match a conditional button (see the staleness check).
const _conditionalAllowlist = <String, String>{};

final _otherButton = RegExp(
  r'(?<![\w.])(?!FloatingActionButton\b)(\w*Button)(?:\.\w+)?\s*\(',
);
final _conditional = RegExp(r'(?<![?.])\?(?![?.])|\bswitch\b|\bif\b');

/// The offset just past the value of the named argument whose value starts at
/// [from] in [code]: the `,` or closing delimiter that ends it at its own
/// depth.
int _argEnd(String code, int from) {
  var depth = 0;
  for (var i = from; i < code.length; i++) {
    final c = code[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) {
      if (depth == 0) return i;
      depth--;
    }
    if (c == ',' && depth == 0) return i;
  }
  return code.length;
}

/// `path:line` for each floating button in [source] whose icon is not New,
/// Edit or Import, and for any other kind of button (a `FilledButton.icon`,
/// say) given to a `floatingActionButton:` slot.
List<String> strayFabsIn(String path, String source) {
  final code = codeOnly(source);
  final lines = <int>{
    for (final match in _fab.allMatches(code))
      if (!_allowedIcon.hasMatch(
        code.substring(match.end - 1, closingDelimiter(code, match.end - 1)),
      ))
        lineAt(source, match.start),
  };
  for (final slot in RegExp(
    r'(?<![\w.])floatingActionButton\s*:(?!:)',
  ).allMatches(code)) {
    final value = code.substring(slot.end, _argEnd(code, slot.end));
    for (final b in _otherButton.allMatches(value)) {
      lines.add(lineAt(source, slot.end + b.start));
    }
  }
  return [for (final line in lines.toList()..sort()) '$path:$line'];
}

/// `path:line` for each floating button in [source] whose icon, child or
/// label is chosen by a condition (`dirty ? save : add`, a `switch`).
List<String> conditionalFabsIn(String path, String source) {
  final code = codeOnly(source);
  return [
    for (final match in _fab.allMatches(code))
      if (callArgs(source, match.end - 1, code: code).any(
        (a) =>
            const {'icon', 'child', 'label'}.contains(a.name) &&
            _conditional.hasMatch(code.substring(a.start, a.end)),
      ))
        '$path:${lineAt(source, match.start)}',
  ];
}

/// Whether [source] floats a button at all.
bool floatsAButton(String source) => _fab.hasMatch(codeOnly(source));

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

  test('no floating button changes its icon or label with state, unless '
      'listed', () {
    final found = [
      for (final f in files)
        ...conditionalFabsIn(
          f.path.replaceAll(r'\', '/'),
          f.readAsStringSync(),
        ),
    ];
    final flaggedFiles = {
      for (final f in found) f.substring(0, f.lastIndexOf(':')),
    };
    expect(
      [
        for (final f in found)
          if (!_conditionalAllowlist.containsKey(
            f.substring(0, f.lastIndexOf(':')),
          ))
            f,
      ],
      isEmpty,
      reason:
          'a floating button that is one thing now and another later can be '
          'a floating Save; give it one job, or list it with what it switches '
          'between',
    );
    for (final path in _conditionalAllowlist.keys) {
      expect(
        flaggedFiles,
        contains(path),
        reason: '$path: remove the stale entry',
      );
    }
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
    // Another kind of button in the floating slot is a floating button too,
    // and the scan reads the slot to its end, across lines.
    const filledSave = '''
      Scaffold(
        floatingActionButton: dirty
            ? FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: Text(l10n.commonSave),
              )
            : null,
        body: TextButton(onPressed: null, child: Text('not floating')),
      )''';
    expect(strayFabsIn('x.dart', filledSave), ['x.dart:3']);
    expect(
      strayFabsIn('x.dart', 'Scaffold(floatingActionButton: _fab(), body: b)'),
      isEmpty,
    );
    // Prose naming a floating button is not one.
    expect(
      floatsAButton('// FloatingActionButton(child: Icon(Icons.save))'),
      isFalse,
    );
  });

  test('the scanner flags a floating button whose icon or label is '
      'conditional', () {
    const saveOrNew = '''
      FloatingActionButton.extended(
        onPressed: dirty ? _save : _new,
        icon: Icon(dirty ? Icons.save : Icons.add),
        label: Text(l10n.venueNew),
      )''';
    const labelSwitch = '''
      adaptiveExtendedFab(
        context,
        icon: const Icon(Icons.add),
        label: switch (mode) { Mode.a => l10n.a, Mode.b => l10n.b },
      )''';
    const plain = '''
      FloatingActionButton.extended(
        onPressed: busy ? null : _new,
        icon: const Icon(Icons.add),
        label: Text(widget.title ?? l10n.venueNew),
      )''';
    expect(conditionalFabsIn('x.dart', saveOrNew), ['x.dart:1']);
    expect(conditionalFabsIn('x.dart', labelSwitch), ['x.dart:1']);
    // A condition on onPressed, or a `??`, is not a change of job.
    expect(conditionalFabsIn('x.dart', plain), isEmpty);
  });
}
