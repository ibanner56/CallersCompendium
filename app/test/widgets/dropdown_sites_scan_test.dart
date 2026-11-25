import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every dropdown in the app, form fields and list rows' compact controls
/// alike, file by file in source order, by the source
/// text of its `key` argument and of its `filterable` argument (whether typing
/// filters its menu; `false` when it is left out).
///
/// A dropdown is select-only (no typing, so a tap on touch never raises the
/// keyboard) unless its list is long or grows with the user's own data. Adding
/// a dropdown, or changing one's choice, means updating this table: the choice
/// is made on purpose, not by default.
const _sites = <String, List<(String, String)>>{
  'lib/src/screens/compound_shorthand_editor_screen.dart': [
    ("const ValueKey('compound-shorthand-compound')", 'true'),
  ],
  'lib/src/screens/custom_fields_screen.dart': [
    ("const ValueKey('cf-type')", 'false'),
  ],
  'lib/src/screens/dance_editor/custom_field_editor.dart': [
    (r"ValueKey('custom-${def.id}-choice')", 'true'),
  ],
  'lib/src/screens/dance_editor/dance_editor_form.dart': [
    ("const ValueKey('form-field')", 'false'),
    ("const ValueKey('formation-field')", 'false'),
  ],
  'lib/src/screens/dance_editor/named_phrases_editor.dart': [
    (r"ValueKey('named-phrase-$index-name')", 'false'),
  ],
  'lib/src/screens/dance_editor/editor_fields.dart': [
    (r"ValueKey('$fieldKey-field')", 'false'),
    ("const ValueKey('level-field')", 'true'),
    (r"ValueKey('${widget.fieldKey}-month')", 'true'),
    (r"ValueKey('${widget.fieldKey}-day')", 'true'),
  ],
  'lib/src/screens/dance_editor/links_editor.dart': [
    (r"ValueKey('link-kind-${draft.id}')", 'false'),
  ],
  'lib/src/screens/dialect_editor_screen.dart': [
    // Every move a dialect can rename, plus the user's own figures.
    ("const ValueKey('dialect-add-move')", 'true'),
    ("const ValueKey('dialect-add-move-wording')", 'true'),
    ("const ValueKey('dialect-add-dancer')", 'false'),
  ],
  'lib/src/screens/import_review_screen.dart': [
    ("const ValueKey('import-source-select')", 'false'),
  ],
  'lib/src/screens/import_csv_mapping.dart': [
    ("const ValueKey('text-dance-start')", 'false'),
    ("const ValueKey('csv-separator')", 'false'),
    // Some thirty column targets plus the caller's custom fields.
    (r"ValueKey('csv-column-$index')", 'true'),
  ],
  'lib/src/screens/glossary/compound_editor_screen.dart': [
    ("const ValueKey('glossary-entry-form')", 'false'),
    (r"ValueKey('compound-param-$i-kind')", 'false'),
    (r"ValueKey('compound-binding-$index-$slot')", 'true'),
  ],
  'lib/src/screens/glossary/user_figure_switch_screen.dart': [
    (r"ValueKey('user-figure-switch-param-${param.key}')", 'false'),
    (
      r"ValueKey('user-figure-switch-choice-${param.key}-${choice.id}-$mappedTo',)",
      'false',
    ),
  ],
  'lib/src/screens/program_editor_screen.dart': [
    ("const ValueKey('program-status')", 'false'),
    ("const ValueKey('program-pay-currency')", 'true'),
    ("const ValueKey('program-dialect')", 'true'),
  ],
  'lib/src/screens/settings/calling_card_section.dart': [
    ("const ValueKey('calling-card-size')", 'false'),
    ("const ValueKey('calling-card-unit')", 'false'),
  ],
  'lib/src/screens/settings/event_rules_screen.dart': [
    (
      "const ValueKey('event-rule-search')",
      'searches.length >= appDropdownFilterFrom',
    ),
  ],
  'lib/src/screens/settings/defaults_section.dart': [
    ("const ValueKey('defaults-collection-sort')", 'false'),
    ("const ValueKey('defaults-program-sort')", 'false'),
    ("const ValueKey('defaults-dance-form')", 'false'),
    ("const ValueKey('defaults-dance-formation')", 'false'),
    ("const ValueKey('defaults-dance-progression')", 'false'),
  ],
  'lib/src/screens/settings/general_section.dart': [
    ("const ValueKey('general-undo-prompt-seconds')", 'false'),
    ("const ValueKey('general-soft-delete-retention')", 'false'),
    ("const ValueKey('backup-reminder-cadence')", 'false'),
  ],
  'lib/src/screens/settings/calendar_settings_tiles.dart': [
    ("const ValueKey('calendar-settings-window-field')", 'false'),
    ("const ValueKey('calendar-settings-startup-mode-field')", 'false'),
  ],
  'lib/src/screens/settings/experimental_section.dart': [
    ("const ValueKey('experimental-event-rule-order-field')", 'false'),
  ],
  'lib/src/screens/settings/matrix_column_editor.dart': [
    ("const ValueKey('matrix-parameterized-move')", 'true'),
    (r"ValueKey('matrix-compound-step-move-$index')", 'true'),
  ],
  'lib/src/screens/settings/program_templates_screen.dart': [
    ("const ValueKey('defaults-program-template-default')", 'true'),
    // The caller's own saved searches: typing filters once the list is long.
    (
      "const ValueKey('program-template-rule-search')",
      'searches.length >= appDropdownFilterFrom',
    ),
  ],
  'lib/src/screens/settings/program_section.dart': [
    ("const ValueKey('program-venue-call-count')", 'false'),
  ],
  'lib/src/screens/settings/regional_section.dart': [
    ("const ValueKey('regional-language')", 'false'),
    ("const ValueKey('regional-date-format')", 'false'),
    ("const ValueKey('regional-first-day-of-week-dropdown')", 'false'),
  ],
  'lib/src/screens/settings/suggestion_settings_screen.dart': [
    // Three fixed choices each: select-only.
    ("const ValueKey('suggestion-curve-shape')", 'false'),
    ("const ValueKey('suggestion-venue-window')", 'false'),
  ],
  'lib/src/widgets/advanced_query_builder.dart': [
    (r"ValueKey('group-kind-${group.id}')", 'false'),
    (r"ValueKey('tag-${node.id}')", 'true'),
    (r"ValueKey('fig-group-kind-${group.id}')", 'false'),
    // Grows only through a dance's named phrases, beyond the standard A1 to
    // B2, so it stays a short list: select-only.
    (r"ValueKey('section-${figure.id}')", 'false'),
    (r"ValueKey('param-${figure.id}-$paramKey')", 'false'),
  ],
  'lib/src/widgets/batch_custom_field_dialog.dart': [
    (r"ValueKey('batch-custom-field-value-${def.id}')", 'true'),
    ("const ValueKey('batch-custom-field-key')", 'true'),
  ],
  'lib/src/widgets/collection_search_controls.dart': [('fieldKey', 'false')],
  'lib/src/widgets/figure_param_editors.dart': [
    ('ValueKey(_key)', 'selectable.length >= appDropdownFilterFrom'),
  ],
  'lib/src/widgets/user_figure_argument_editor.dart': [
    ('ValueKey(_key)', 'true'),
    ('ValueKey(_key)', 'values.length + 1 >= appDropdownFilterFrom'),
  ],
};

const _wrapper = 'lib/src/widgets/app_dropdown_field.dart';

/// Files that may still build a plain `DropdownButton`, each with the reason
/// its menu can go without the High contrast outline. A plain
/// `DropdownButton` paints its menu with a fixed decoration that no theme can
/// outline; a list row's trailing control uses `AppDropdownField(compact:
/// true)` instead. Empty: every dropdown in the app is outlined.
const _plainDropdownAllowlist = <String, String>{};

Iterable<File> _dartSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no DropdownButtonFormField comes back: its menu cannot take the High '
      'contrast outline', () {
    final offenders = [
      for (final file in _dartSources())
        if (_code(file.readAsStringSync()).contains('DropdownButtonFormField'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('no plain DropdownButton comes back outside the allowlist: its menu '
      'cannot take the High contrast outline', () {
    final offenders = [
      for (final file in _dartSources())
        if (_buildsPlainDropdown(file.readAsStringSync()) &&
            !_plainDropdownAllowlist.containsKey(
              file.path.replaceAll(r'\', '/'),
            ))
          file.path.replaceAll(r'\', '/'),
    ];
    expect(offenders, isEmpty);
    // An allowlisted file that no longer needs its entry loses it, so the
    // list never grows stale.
    for (final path in _plainDropdownAllowlist.keys) {
      expect(
        _buildsPlainDropdown(File(path).readAsStringSync()),
        isTrue,
        reason: '$path no longer builds a plain DropdownButton',
      );
    }
  });

  test('the plain DropdownButton scan finds a use and skips prose', () {
    // Positive controls: a generic or bare construction is a use, wherever it
    // starts a line; the same words in a comment, or another widget whose
    // name merely starts with them, are not.
    expect(
      _buildsPlainDropdown('final d = DropdownButton<int>(value: 1);'),
      isTrue,
    );
    expect(_buildsPlainDropdown('child: DropdownButton(\n  value: 1,'), isTrue);
    expect(_buildsPlainDropdown('const DropdownButton<String>('), isTrue);
    expect(
      _buildsPlainDropdown('/// a [DropdownButton<int>] asserts'),
      isFalse,
    );
    expect(_buildsPlainDropdown('// DropdownButton<int>('), isFalse);
    expect(_buildsPlainDropdown('DropdownButtonHideUnderline('), isFalse);
    expect(_buildsPlainDropdown('DropdownButtonFormField<int>('), isFalse);
  });

  test('the scan sees code, not comments', () {
    // Positive control: the wrapper names the old widget in its doc comment,
    // which the raw text shows and the code-only view does not.
    final src = File(_wrapper).readAsStringSync();
    expect(src, contains('DropdownButtonFormField'));
    expect(_code(src), isNot(contains('DropdownButtonFormField')));
    expect(_code('a; // x\nb'), 'a; \nb');
  });

  test('every form dropdown has a recorded typing choice', () {
    final found = <String, List<(String, String)>>{};
    for (final file in _dartSources()) {
      final path = file.path.replaceAll(r'\', '/');
      if (path == _wrapper) continue;
      final src = file.readAsStringSync();
      for (final m in RegExp(r'AppDropdownField<').allMatches(src)) {
        // The call's own `(`, after the type arguments.
        var depth = 0;
        var i = m.end - 1;
        for (; i < src.length; i++) {
          if (src[i] == '<') depth++;
          if (src[i] == '>' && --depth == 0) break;
        }
        final open = src.indexOf('(', i);
        final args = _topLevelArgs(src, open);
        (found[path] ??= []).add((
          args['key'] ?? '',
          args['filterable'] ?? 'false',
        ));
      }
    }
    expect(found, _sites);
  });
}

/// Whether [src] constructs a plain `DropdownButton` (with or without type
/// arguments) in code, not in a comment.
bool _buildsPlainDropdown(String src) =>
    RegExp(r'\bDropdownButton\s*(<|\()').hasMatch(_code(src));

/// [src] with its `//` comments blanked, so prose naming a widget is not read
/// as a use of it. Quotes are tracked, so a `//` inside a string is kept.
String _code(String src) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      out.write(c);
      if (c == r'\' && i + 1 < src.length) {
        out.write(src[++i]);
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      final end = src.indexOf('\n', i);
      if (end < 0) break;
      i = end - 1;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

/// The named arguments of the call whose `(` is at [open], at the call's own
/// nesting depth only, mapped to their source text with comments removed.
/// Walks delimiters (and skips string literals and line comments), so a
/// multi-line or nested argument is read whole.
Map<String, String> _topLevelArgs(String src, int open) {
  final args = <String, String>{};
  var depth = 0;
  var argStart = open + 1;
  String? quote;
  void finish(int end) {
    final arg = _code(src.substring(argStart, end)).trim();
    final named = RegExp(r'^(\w+)\s*:\s*([\s\S]*)$').firstMatch(arg);
    if (named != null) {
      args[named.group(1)!] = named
          .group(2)!
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('( ', '(')
          .replaceAll(' )', ')');
    }
  }

  for (var i = open; i < src.length; i++) {
    final c = src[i];
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
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      i = src.indexOf('\n', i);
    } else if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
      if (depth == 0) {
        finish(i);
        return args;
      }
    } else if (c == ',' && depth == 1) {
      finish(i);
      argStart = i + 1;
    }
  }
  return args;
}
