import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/settings/matrix_column_editor.dart';
import 'package:compendium_app/src/data/program_matrix_column_config_scope.dart';

import 'support/l10n_harness.dart';

/// A small taxonomy (three plain "known" moves) so the editor renders a handful
/// of rows that all fit on screen — the full contra taxonomy has ~100 columns,
/// which is orthogonal to what these tests exercise and forces flaky scrolling.
final _smallTaxonomy = Taxonomy(
  version: contraTaxonomy.version,
  form: contraTaxonomy.form,
  moves: [
    contraTaxonomy.moves['do_si_do']!,
    contraTaxonomy.moves['balance']!,
    contraTaxonomy.moves['petronella']!,
  ],
);

final _parameterizedTaxonomy = Taxonomy(
  version: contraTaxonomy.version,
  form: contraTaxonomy.form,
  moves: [
    contraTaxonomy.moves['swing']!,
    contraTaxonomy.moves['do_si_do']!,
    contraTaxonomy.moves['balance']!,
    contraTaxonomy.moves['petronella']!,
  ],
);

/// A stateful harness that renders [MatrixColumnEditor], keeps the edited
/// config in state (so the editor re-reads it after each change, exactly as the
/// real settings pane does), and exposes the latest config to assertions.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.initial,
    required this.onChanged,
    required this.taxonomy,
  });

  final MatrixColumnConfig initial;
  final ValueChanged<MatrixColumnConfig> onChanged;
  final Taxonomy taxonomy;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late MatrixColumnConfig _config = widget.initial;

  @override
  Widget build(BuildContext context) => MatrixColumnEditor(
    config: _config,
    dialect: Dialect.larksRobins,
    taxonomy: widget.taxonomy,
    onConfigChanged: (config) {
      setState(() => _config = config);
      widget.onChanged(config);
    },
  );
}

Future<MatrixColumnConfig Function()> _pumpEditor(
  WidgetTester tester, {
  MatrixColumnConfig initial = MatrixColumnConfig.empty,
  Taxonomy? taxonomy,
}) async {
  final activeTaxonomy = taxonomy ?? _smallTaxonomy;
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var latest = initial;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: _Harness(
          initial: initial,
          taxonomy: activeTaxonomy,
          onChanged: (config) => latest = config,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => latest;
}

void main() {
  final tax = _smallTaxonomy;
  final catalogIds = [for (final c in builtInColumnCatalog(tax)) c.moveId];

  MatrixColumn columnFor(String id) =>
      builtInColumnCatalog(tax).firstWhere((c) => c.moveId == id);

  group('MatrixColumnEditor', () {
    testWidgets('removing a column adds its id to hidden and the matrix '
        'drops it from display', (tester) async {
      final read = await _pumpEditor(tester);
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-remove-do_si_do')),
      );
      await tester.pumpAndSettle();

      final config = read();
      expect(config.hidden, contains('do_si_do'));

      // The matrix honours it: a dance whose only figure is do_si_do no longer
      // shows that column.
      final dance = Dance(
        id: 'd1',
        title: 'D',
        figures: [testFigure(move: 'do_si_do', params: const {})],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        formation: const Formation(FormationShape.dupleImproper),
      );
      final matrix = buildProgramMatrix([dance], taxonomy: tax, config: config);
      expect(matrix.columns.map((c) => c.moveId), isNot(contains('do_si_do')));
    });

    testWidgets('renaming a column writes renames[id] and changes the header '
        'label used by the table and PDF', (tester) async {
      final read = await _pumpEditor(tester);
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-rename-do_si_do')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('matrix-column-rename-field')),
        'Dosido',
      );
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-rename-confirm')),
      );
      await tester.pumpAndSettle();

      final config = read();
      expect(config.renames['do_si_do'], 'Dosido');
      // matrixColumnLabel is the single label path both the on-screen table and
      // the PDF export route through, so a rename there covers both.
      expect(
        matrixColumnLabel(
          columnFor('do_si_do'),
          tax,
          Dialect.larksRobins,
          config: config,
        ),
        'Dosido',
      );
    });

    testWidgets('reordering writes the full displayed order to config.order', (
      tester,
    ) async {
      final read = await _pumpEditor(tester);
      final rlv = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      // Move the first column to index 2 (pre-adjusted onReorderItem semantics).
      rlv.onReorderItem!(0, 2);
      await tester.pumpAndSettle();

      final order = read().order;
      expect(order.length, catalogIds.length);
      final expected = [...catalogIds];
      final moved = expected.removeAt(0);
      expected.insert(2, moved);
      expect(order, expected);
    });

    testWidgets('restore removed defaults clears hidden, keeps renames, and '
        'appends customs after built-ins by label', (tester) async {
      final initial = MatrixColumnConfig(
        order: const ['do_si_do', 'balance'],
        hidden: const {'petronella'},
        renames: const {'do_si_do': 'Dosido', 'param:z': 'Alpha'},
        parameterized: const [
          ParameterizedColumn(id: 'param:z', baseMove: 'swing'),
        ],
      );
      final read = await _pumpEditor(tester, initial: initial);
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-reset-removed')),
      );
      await tester.pumpAndSettle();

      final config = read();
      expect(config.hidden, isEmpty);
      expect(config.renames, {'do_si_do': 'Dosido', 'param:z': 'Alpha'});
      // Built-ins back in catalog order, the one custom appended last.
      expect(config.order, [...catalogIds, 'param:z']);
    });

    testWidgets('restore all defaults asks to confirm, then empties config', (
      tester,
    ) async {
      const initial = MatrixColumnConfig(hidden: {'do_si_do'});
      final read = await _pumpEditor(tester, initial: initial);
      await tester.tap(find.byKey(const ValueKey('matrix-column-reset-true')));
      await tester.pumpAndSettle();
      // Nothing changes until the destructive action is confirmed.
      expect(read().isEmpty, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-reset-true-confirm')),
      );
      await tester.pumpAndSettle();
      expect(read().isEmpty, isTrue);
    });

    testWidgets(
      'adds, edits, and labels a parameterized column from taxonomy',
      (tester) async {
        final read = await _pumpEditor(
          tester,
          taxonomy: _parameterizedTaxonomy,
        );
        await tester.tap(
          find.byKey(const ValueKey('matrix-column-add-parameterized')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('matrix-parameterized-move')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('matrix-parameterized-constraint-who')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('matrix-parameterized-label')),
          'Partner swing',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('matrix-parameterized-save')),
        );
        await tester.pumpAndSettle();

        final added = read().parameterized.single;
        expect(added.baseMove, 'swing');
        expect(added.params, {'who': 'partners'});
        expect(read().renames[added.id], 'Partner swing');

        final editFinder = find.byKey(
          ValueKey('matrix-column-edit-details-${added.id}'),
        );
        await tester.scrollUntilVisible(editFinder, 400);
        await tester.tap(editFinder);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('matrix-parameterized-constraint-prefix')),
        );
        await tester.tap(
          find.byKey(const ValueKey('matrix-parameterized-save')),
        );
        await tester.pumpAndSettle();

        expect(read().parameterized.single.params, {
          'who': 'partners',
          'prefix': 'none',
        });
      },
    );

    testWidgets('requires a non-empty parameterized column name', (
      tester,
    ) async {
      await _pumpEditor(tester, taxonomy: _parameterizedTaxonomy);
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-add-parameterized')),
      );
      await tester.pumpAndSettle();

      TextButton saveButton() => tester.widget(
        find.byKey(const ValueKey('matrix-parameterized-save')),
      );
      expect(saveButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('matrix-parameterized-label')),
        '   ',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('matrix-parameterized-label')),
        'Partner swing',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);
    });

    testWidgets('deleting a parameterized column removes all references', (
      tester,
    ) async {
      const id = 'param:partner-swing';
      final initial = MatrixColumnConfig(
        order: const [id],
        hidden: const {id},
        renames: const {id: 'Partner swing'},
        parameterized: const [
          ParameterizedColumn(
            id: id,
            baseMove: 'swing',
            params: {'who': 'partners'},
          ),
        ],
      );
      final read = await _pumpEditor(tester, initial: initial);
      await tester.tap(
        find.byKey(const ValueKey('matrix-column-delete-param:partner-swing')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('matrix-column-delete-confirm-param:partner-swing'),
        ),
      );
      await tester.pumpAndSettle();

      final config = read();
      expect(config.parameterized, isEmpty);
      expect(config.order, isEmpty);
      expect(config.hidden, isEmpty);
      expect(config.renames, isEmpty);
    });

    testWidgets('repairs stale parameterized definitions when editing', (
      tester,
    ) async {
      const id = 'param:stale-column';
      final initial = MatrixColumnConfig(
        order: const [id],
        parameterized: const [
          ParameterizedColumn(
            id: id,
            baseMove: 'removed_move',
            params: {'removed_param': 'stale'},
          ),
        ],
      );
      final read = await _pumpEditor(
        tester,
        initial: initial,
        taxonomy: _parameterizedTaxonomy,
      );
      final editFinder = find.byKey(
        const ValueKey('matrix-column-edit-details-param:stale-column'),
      );
      await tester.scrollUntilVisible(editFinder, 400);
      await tester.tap(editFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('matrix-parameterized-move')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('matrix-parameterized-constraint-removed_param'),
        ),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('matrix-parameterized-label')),
        'Repaired column',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('matrix-parameterized-save')));
      await tester.pumpAndSettle();

      expect(read().parameterized.single.baseMove, 'swing');
      expect(read().parameterized.single.params, isEmpty);
    });

    testWidgets('reorders parameterized and built-in columns together', (
      tester,
    ) async {
      const id = 'param:partner-swing';
      final initial = MatrixColumnConfig(
        parameterized: const [ParameterizedColumn(id: id, baseMove: 'swing')],
      );
      final read = await _pumpEditor(tester, initial: initial);
      final rlv = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      final parameterizedIndex = catalogIds.length;
      rlv.onReorderItem!(parameterizedIndex, 0);
      await tester.pumpAndSettle();

      expect(read().order.first, id);
      expect(read().order.length, catalogIds.length + 1);
    });

    testWidgets('editing through the live scope rebuilds an open dependent '
        '(matrix)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<MatrixColumnConfig>(
        MatrixColumnConfig.empty,
      );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: ProgramMatrixColumnConfigScope(
              notifier: notifier,
              child: Column(
                children: [
                  // A stand-in for an open matrix: it depends on the scope and
                  // renders the current hidden-column count, so a rebuild driven
                  // by the notifier is observable.
                  Builder(
                    builder: (context) {
                      final config = ProgramMatrixColumnConfigScope.of(context);
                      return Text(
                        'hidden=${config.hidden.length}',
                        key: const ValueKey('probe'),
                      );
                    },
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) => MatrixColumnEditor(
                        config: ProgramMatrixColumnConfigScope.of(context),
                        dialect: Dialect.larksRobins,
                        taxonomy: _smallTaxonomy,
                        onConfigChanged: (config) => notifier.value = config,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('probe'))).data,
        'hidden=0',
      );

      await tester.tap(
        find.byKey(const ValueKey('matrix-column-remove-do_si_do')),
      );
      await tester.pumpAndSettle();

      // The dependent rebuilt off the notifier — not just the editor.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('probe'))).data,
        'hidden=1',
      );
    });

    testWidgets('renders the full contra taxonomy (~100 columns) with '
        'semantics enabled without a layout assert', (tester) async {
      // Regression guard: an earlier revision embedded the editor inline in the
      // scrolling settings list, where a shrink-wrapped ReorderableListView of
      // ~100 semantics-wrapped drag handles tripped Flutter's
      // '!childSemantics.renderObject._needsLayout' assert. The editor now owns
      // a full-height list on its own screen; this pumps every built-in column
      // with the semantics tree built to prove that path stays clean.
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: MatrixColumnEditor(
              config: MatrixColumnConfig.empty,
              dialect: Dialect.larksRobins,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final catalogSize = builtInColumnCatalog(contraTaxonomy).length;
      expect(catalogSize, greaterThan(50));
      handle.dispose();
    });
  });
}
