import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({required this.drafts});
  final List<FigureDraft> drafts;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FigureListEditor(
            drafts: widget.drafts,
            taxonomy: contraTaxonomy,
            phraseStructure: PhraseStructure.standard,
            onChanged: () => setState(() {}),
            onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
            onDelete: (d) => setState(() => widget.drafts.remove(d)),
            onReorder: (o, n) {},
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, List<FigureDraft> drafts) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_Host(drafts: drafts));
  await tester.pumpAndSettle();
}

void _select(WidgetTester tester, Key fieldKey, int base, int extent) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(fieldKey),
      matching: find.byType(EditableText),
    ),
  );
  editable.controller.selection = TextSelection(
    baseOffset: base,
    extentOffset: extent,
  );
}

void main() {
  testWidgets('bold button wraps the note selection with * delimiters', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft(move: 'swing')];
    await _pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-0-add-note')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'big smooth swing',
    );
    await tester.pumpAndSettle();

    // Select the word "smooth" (offsets 4..10).
    _select(tester, const ValueKey('figure-0-note'), 4, 10);
    await tester.tap(find.byKey(const ValueKey('figure-0-note-bold')));
    await tester.pumpAndSettle();

    expect(drafts.single.note, 'big *smooth* swing');
  });

  testWidgets('underline button wraps the note selection with _ delimiters', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft(move: 'swing')];
    await _pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-0-add-note')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'balance then swing',
    );
    await tester.pumpAndSettle();

    _select(tester, const ValueKey('figure-0-note'), 0, 7); // "balance"
    await tester.tap(find.byKey(const ValueKey('figure-0-note-underline')));
    await tester.pumpAndSettle();

    expect(drafts.single.note, '_balance_ then swing');
  });
}
