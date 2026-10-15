import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every place that shows a dance's figures renders a use of one of the
/// user's own figures live (#1023), so it builds its renderer with the user's
/// figures: `UserFiguresScope.rendererOf(context)`, or a `FigureRenderer(…)`
/// given `userFigures:`. A renderer built without them shows such a use's
/// stored line, which may predate an edit to the figure.
///
/// The sites below build one without them, each for a reason it never shows a
/// dance's figures. A new one fails this test until it is justified here, so a
/// new display of a dance cannot quietly show stale wording.
const Map<String, int> _allowed = {
  // A fallback for a caller that passes no renderer; every caller passes the
  // live one (`DanceExportActions`, `ProgramExportMenu`).
  'lib/src/export/dance_pdf.dart': 1,
  'lib/src/export/program_pdf.dart': 1,
  // Built-in moves' names and examples, the user's glossary text.
  'lib/src/glossary/figure_titles.dart': 1,
  'lib/src/screens/glossary/glossary_screen.dart': 1,
  'lib/src/screens/glossary/custom_figure_detail.dart': 1,
  'lib/src/screens/glossary/compound_editor_screen.dart': 1,
  'lib/src/screens/compound_shorthand_editor_screen.dart': 1,
  // Free text, formation labels and link labels; the figures go to the live
  // renderer.
  'lib/src/screens/dance_detail_screen.dart': 2,
  'lib/src/screens/program_summary_screen.dart': 2,
  'lib/src/screens/program_editor_screen.dart': 2,
  'lib/src/screens/sync_conflict_details.dart': 1,
  'lib/src/screens/perform_adjust_sheet.dart': 1,
  'lib/src/screens/import_review_screen.dart': 1,
  'lib/src/widgets/dance_list_tile.dart': 2,
  'lib/src/widgets/program_slot_list_editor.dart': 3,
  'lib/src/widgets/program_export_menu.dart': 1,
  // The editor's own text round trip, move names, parameter editors, and
  // previews of a built-in move or its wording; a row's summary is live.
  'lib/src/screens/dance_editor/dance_editor_controller.dart': 1,
  'lib/src/widgets/figure_list_editor.dart': 9,
  'lib/src/widgets/move_autocomplete.dart': 1,
  'lib/src/widgets/compound_argument_editor.dart': 1,
  'lib/src/widgets/user_figure_argument_editor.dart': 1,
  'lib/src/screens/settings/defaults_section.dart': 1,
  // Dialect templates, walkthrough snippet signatures and figure shorthands:
  // built-in moves, not a dance.
  'lib/src/screens/dialect_editor_screen.dart': 3,
  'lib/src/screens/walkthrough_snippets_screen.dart': 1,
  'lib/src/screens/shorthand_mappings_screen.dart': 2,
  'lib/src/screens/import_shorthand_seed_screen.dart': 1,
};

/// [source] with every comment blanked out, positions kept.
String _withoutComments(String source) => source
    .replaceAllMapped(
      RegExp(r'/\*.*?\*/', dotAll: true),
      (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
    )
    .replaceAllMapped(RegExp(r'//[^\n]*'), (m) => ' ' * m[0]!.length);

/// How many `FigureRenderer(…)` constructions in [source] pass no
/// `userFigures:`, found by walking each one's parentheses to its close, so a
/// construction spread over several lines is read whole.
int bareConstructions(String source) {
  final text = _withoutComments(source);
  var count = 0;
  for (final match in RegExp(r'\bFigureRenderer\(').allMatches(text)) {
    var depth = 1;
    var i = match.end;
    while (depth > 0 && i < text.length) {
      final char = text[i];
      if (char == '(') depth++;
      if (char == ')') depth--;
      i++;
    }
    if (!text.substring(match.end, i).contains('userFigures:')) count++;
  }
  return count;
}

void main() {
  test('the scanner reads a construction whole, and ignores comments', () {
    expect(bareConstructions('final r = FigureRenderer(contraTaxonomy);'), 1);
    expect(
      bareConstructions(
        'final r = FigureRenderer(\n  contraTaxonomy,\n  userFigures: c,\n);',
      ),
      0,
    );
    expect(
      bareConstructions('final r = FigureRenderer(f(x), userFigures: c);'),
      0,
    );
    expect(bareConstructions('// FigureRenderer(contraTaxonomy)'), 0);
  });

  test('every renderer built without the user\'s figures is one that never '
      'shows a dance\'s figures (#1023)', () {
    final found = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/')) continue;
      final count = bareConstructions(entity.readAsStringSync());
      if (count > 0) found[path] = count;
    }
    expect(
      found,
      _allowed,
      reason:
          'A FigureRenderer built without userFigures shows a use of the '
          "user's own figure as its stored line. Use "
          'UserFiguresScope.rendererOf(context) where a dance\'s figures are '
          'shown; otherwise add the site to _allowed with why it never shows '
          "a dance's figures.",
    );
  });
}
