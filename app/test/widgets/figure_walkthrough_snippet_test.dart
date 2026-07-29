import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// Host that wires the #411 per-figure walkthrough-snippet callbacks against an
/// in-memory [WalkthroughSnippetLibrary], mirroring what the dance editor form
/// does, so the learn-on-first-entry + divergence-prompt flow can be tested.
class _Host extends StatefulWidget {
  const _Host({required this.drafts, required this.library});

  final List<FigureDraft> drafts;
  final WalkthroughSnippetLibrary library;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late WalkthroughSnippetLibrary _library = widget.library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FigureListEditor(
            drafts: widget.drafts,
            taxonomy: contraTaxonomy,
            phraseStructure: PhraseStructure.standard,
            onChanged: () => setState(() {}),
            onAdd: () {},
            onDelete: (_) {},
            onReorder: (_, _) {},
            snippetLibraryDefaultFor: (draft) {
              final figure = draft.toFigure();
              if (figure == null) return null;
              return _library.resolve(
                figureSnippetSignature(figure, contraTaxonomy),
              );
            },
            onSnippetCommitted: (draft) async {
              final figure = draft.toFigure();
              if (figure == null) return;
              final signature = figureSnippetSignature(figure, contraTaxonomy);
              final text = (draft.walkthroughOverride ?? '').trim();
              if (signature == null || text.isEmpty) return;
              final existing = _library.resolve(signature);
              if (existing == null) {
                // Learn-on-first-entry.
                setState(() {
                  _library = _library.withSnippet(signature, text);
                  draft.walkthroughOverride = null;
                });
              }
            },
          ),
        ),
      ),
    );
  }

  WalkthroughSnippetLibrary get library => _library;
}

Future<void> _pump(WidgetTester tester, _Host host) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

Future<void> _openFigure(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'per-figure walkthrough field pre-fills from the library default',
    (tester) async {
      final swing = Figure(move: 'swing', params: {'who': 'partners'});
      final signature = figureSnippetSignature(swing, contraTaxonomy)!;
      final library = WalkthroughSnippetLibrary.empty.withSnippet(
        signature,
        'Swing your partner.',
      );
      final drafts = [FigureDraft.fromFigure(swing)];

      await _pump(tester, _Host(drafts: drafts, library: library));
      await _openFigure(tester, 0);

      // The snippet field is shown pre-populated (no "Add walkthrough step"
      // button, because a default resolves).
      expect(find.text('Swing your partner.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('figure-0-add-walkthrough')),
        findsNothing,
      );
    },
  );

  testWidgets('learn-on-first-entry stores a new snippet on blur', (
    tester,
  ) async {
    final swing = Figure(move: 'swing', params: {'who': 'partners'});
    final signature = figureSnippetSignature(swing, contraTaxonomy)!;
    final drafts = [FigureDraft.fromFigure(swing)];
    final host = _Host(
      drafts: drafts,
      library: WalkthroughSnippetLibrary.empty,
    );

    await _pump(tester, host);
    await _openFigure(tester, 0);

    // No default yet: the field is behind the reveal button.
    final addButton = find.byKey(const ValueKey('figure-0-add-walkthrough'));
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-walkthrough')),
      'Balance and swing.',
    );
    // Blur the field to trigger the commit (learn-on-first-entry).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final state = tester.state<State<_Host>>(find.byType(_Host)) as _HostState;
    expect(state.library.resolve(signature), 'Balance and swing.');
    // The learned snippet is the library default, so no per-dance override.
    expect(drafts.single.walkthroughOverride, isNull);
  });
}
