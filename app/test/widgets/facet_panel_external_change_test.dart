// A custom text or number filter's field shows what the facets hold, however
// they came to hold it (#2325). It used to follow an outside change only when
// the value was cleared, so opening a search for X over one for Y left Y on
// screen while X filtered.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/facet_panel.dart';
import '../support/l10n_harness.dart';

final _text = CustomFieldDef(
  id: 'ft',
  key: 'caller_note',
  label: 'Caller note',
  type: CustomFieldType.text,
);
final _number = CustomFieldDef(
  id: 'fn',
  key: 'tempo',
  label: 'Tempo',
  type: CustomFieldType.number,
);

/// Hosts a [FacetPanel] over [facets], which a test may replace wholesale
/// (as a host does when it opens a given panel state) or edit in place.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.facets});

  final FacetSelections facets;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late FacetSelections facets = widget.facets;

  void replace(FacetSelections next) => setState(() => facets = next);

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => FacetPanel(
    facets: facets,
    forms: const [],
    formations: const [],
    progressions: const [],
    statuses: const [],
    levels: const [],
    hasMixedLevel: false,
    hasMixer: false,
    hasRating: false,
    authors: const [],
    tags: const [],
    citedSources: const [],
    tunes: const [],
    choiceFields: const [],
    booleanFields: const [],
    textFields: [_text],
    numberFields: [_number],
    onChanged: rebuild,
  );
}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester,
  FacetSelections facets,
) async {
  final key = GlobalKey<_HostState>();
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: _Host(key: key, facets: facets),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  testWidgets('a panel state put in place of another shows its own text and '
      'number values, not the old ones', (tester) async {
    final before = FacetSelections()
      ..textValues['ft'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: 'swing',
      )
      ..numberValues['fn'] = const NumberFacetState(
        op: CustomFieldOp.eq,
        lo: 112,
      );
    final host = await _pump(tester, before);
    expect(_fieldText(tester, 'cf-text-ft-input'), 'swing');
    expect(_fieldText(tester, 'cf-num-fn-lo'), '112');

    final after = FacetSelections()
      ..textValues['ft'] = const TextFacetState(
        op: CustomFieldOp.equals,
        value: 'balance',
      )
      ..numberValues['fn'] = const NumberFacetState(
        op: CustomFieldOp.between,
        lo: 100,
        hi: 120,
      );
    host.currentState!.replace(after);
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'cf-text-ft-input'), 'balance');
    expect(_fieldText(tester, 'cf-num-fn-lo'), '100');
    expect(_fieldText(tester, 'cf-num-fn-hi'), '120');
    // The operator chips follow too.
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('cf-text-ft-equals')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('cf-num-fn-between')))
          .selected,
      isTrue,
    );
    // And the shown values are what filters.
    expect(after.textValues['ft']!.value, 'balance');
    expect(after.numberValues['fn']!.lo, 100);
  });

  testWidgets('Clear all still empties the fields', (tester) async {
    final facets = FacetSelections()
      ..textValues['ft'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: 'swing',
      )
      ..numberValues['fn'] = const NumberFacetState(
        op: CustomFieldOp.gt,
        lo: 5,
      );
    final host = await _pump(tester, facets);
    facets.clear();
    host.currentState!.rebuild();
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-text-ft-input'), isEmpty);
    expect(_fieldText(tester, 'cf-num-fn-lo'), isEmpty);
  });

  testWidgets('what the user types is never rewritten by the rebuild it '
      'causes', (tester) async {
    final facets = FacetSelections();
    await _pump(tester, facets);

    // Trailing space: the facets hold the trimmed text.
    await tester.enterText(
      find.byKey(const ValueKey('cf-text-ft-input')),
      'a ',
    );
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-text-ft-input'), 'a ');
    expect(facets.textValues['ft']!.value, 'a');

    // A half-typed number is no value yet, so nothing filters; the field
    // keeps what was typed.
    await tester.enterText(find.byKey(const ValueKey('cf-num-fn-lo')), '-');
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-num-fn-lo'), '-');
    expect(facets.numberValues, isEmpty);

    // Between, with only its first bound typed so far: no value yet either.
    await tester.tap(find.byKey(const ValueKey('cf-num-fn-between')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cf-num-fn-lo')), '5');
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-num-fn-lo'), '5');
    expect(facets.numberValues, isEmpty);
  });

  testWidgets('text typed that is no value yet is emptied by Clear all', (
    tester,
  ) async {
    // Between with only its lower bound, and spaces in a text filter, write
    // nothing, so nothing in the facets changes when they are cleared; the
    // fields must empty anyway, or a later bound would make a filter the user
    // thinks they cleared.
    final facets = FacetSelections()..minRating = 3;
    final host = await _pump(tester, facets);
    await tester.tap(find.byKey(const ValueKey('cf-num-fn-between')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cf-num-fn-lo')), '5');
    await tester.enterText(
      find.byKey(const ValueKey('cf-text-ft-input')),
      '   ',
    );
    await tester.pumpAndSettle();
    expect(facets.numberValues, isEmpty);
    expect(facets.textValues, isEmpty);

    // What a host's Clear all does.
    facets.clear();
    host.currentState!.rebuild();
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-num-fn-lo'), isEmpty);
    expect(_fieldText(tester, 'cf-text-ft-input'), isEmpty);
  });

  testWidgets('a half-typed "-" is emptied by a state with no value for the '
      'field', (tester) async {
    final host = await _pump(tester, FacetSelections());
    await tester.enterText(find.byKey(const ValueKey('cf-num-fn-lo')), '-');
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-num-fn-lo'), '-');

    host.currentState!.replace(FacetSelections());
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'cf-num-fn-lo'), isEmpty);
  });
}
