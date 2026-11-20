import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every form dropdown in the app, file by file in source order, by the source
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
  'lib/src/screens/settings/matrix_column_editor.dart': [
    ("const ValueKey('matrix-parameterized-move')", 'true'),
    (r"ValueKey('matrix-compound-step-move-$index')", 'true'),
  ],
  'lib/src/widgets/advanced_query_builder.dart': [
    (r"ValueKey('tag-${node.id}')", 'true'),
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
