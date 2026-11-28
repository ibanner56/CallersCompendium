import 'package:compendium_app/src/screens/dance_editor/name_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/l10n_harness.dart';
import '../../support/screen_size.dart';

void main() {
  testWidgets(
    'narrow layout: creating a brand-new author from the sheet attaches it, '
    'and the sheet stays open with an empty search, above a simulated '
    'keyboard',
    (tester) async {
      final added = <String>[];
      final created = <String>[];
      await setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: NamePicker(
              fieldKey: 'author',
              selectedIds: const [],
              namesById: const {},
              options: const [(id: 'gene', name: 'Gene Hubert')],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: (name) async {
                created.add(name);
                return 'new-id';
              },
              sheetSemanticLabel: 'Authors',
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('author-field')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Simulate a software keyboard inset, as issue #716 describes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('author-input')),
        'Brand New Author',
      );
      await tester.pumpAndSettle();

      final createOption = find.byKey(
        const ValueKey('author-option-create:Brand New Author'),
      );
      expect(createOption, findsOneWidget);
      final optionRect = tester.getRect(createOption);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

      await tester.tap(createOption);
      await tester.pumpAndSettle();

      expect(created, ['Brand New Author']);
      expect(added, ['new-id']);
      // The sheet stays open and its search clears (issue #402), so a second
      // add can start straight away from an empty query, not the previous
      // typed text.
      expect(find.byType(BottomSheet), findsOneWidget);
      final reopenedField = tester.widget<TextField>(
        find.byKey(const ValueKey('author-input')),
      );
      expect(reopenedField.controller?.text, isEmpty);
    },
  );

  testWidgets(
    'narrow layout: checking an existing author adds it without creating',
    (tester) async {
      final added = <String>[];
      final created = <String>[];
      await setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: NamePicker(
              fieldKey: 'author',
              selectedIds: const [],
              namesById: const {},
              options: const [(id: 'gene', name: 'Gene Hubert')],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: (name) async {
                created.add(name);
                return 'new-id';
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('author-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('author-input')),
        'Gene',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('author-option-gene')));
      await tester.pumpAndSettle();

      expect(added, ['gene']);
      expect(created, isEmpty);
    },
  );

  testWidgets(
    'narrow layout: adding three tags in a row keeps the sheet open each '
    'time (the count matters: the old picker closed after every second add, '
    'issue #894)',
    (tester) async {
      final added = <String>[];
      await setScreenSize(tester, const Size(360, 720));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: NamePicker(
              fieldKey: 'tag',
              selectedIds: const [],
              namesById: const {},
              options: const [
                (id: 'red', name: 'Red'),
                (id: 'blue', name: 'Blue'),
                (id: 'green', name: 'Green'),
              ],
              onAdd: added.add,
              onRemove: (_) {},
              onCreate: (name) async => name,
              sheetSemanticLabel: 'Tags',
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('tag-field')));
      await tester.pumpAndSettle();

      for (final tag in ['red', 'blue', 'green']) {
        expect(
          find.byType(BottomSheet),
          findsOneWidget,
          reason: 'sheet must still be open before picking "$tag"',
        );
        await tester.enterText(find.byKey(const ValueKey('tag-input')), tag);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('tag-option-$tag')));
        await tester.pumpAndSettle();
      }

      expect(added, ['red', 'blue', 'green']);
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'sheet must still be open after the third tag',
      );
    },
  );

  group('multi-select dropdown', _dropDownGroup);
  group('canonical equivalence', _canonicalEquivalenceGroup);
  group('create declined', _createDeclinedGroup);
}

// ---------------------------------------------------------------------------
// The picker's "is this name new?" test must ask the same question the
// repository will ask, or it offers a create the repository then refuses.
//
// Found in review on #1410: the comparison was `toLowerCase()` on raw text,
// while `ChoreographerRepository` looks the incumbent up by
// `normalizeShareableText`, which composes to NFC. With a live "café", typing
// the decomposed form matched nothing here, offered "create", and threw
// `DuplicateNaturalKeyError` out of `onSelected` — an async callback nothing
// awaits — so the author was silently not created. The PR body had claimed this
// path was unreachable; it was not.
//
// Both halves are asserted, because fixing only the exact test would suppress
// "create" while the substring filter still failed to show the row it collides
// with, leaving an empty list and no way forward.

/// "café" composed: U+00E9.
const _nfcCafe = 'caf\u00e9';

/// "café" decomposed: "e" + U+0301 combining acute.
const _nfdCafe = 'cafe\u0301';

void _canonicalEquivalenceGroup() {
  Future<List<String>> pumpAndType(
    WidgetTester tester,
    String typed, {
    required List<NameOption> options,
  }) async {
    final created = <String>[];
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: NamePicker(
            fieldKey: 'author',
            selectedIds: const [],
            namesById: const {},
            options: options,
            onAdd: (_) {},
            onRemove: (_) {},
            onCreate: (name) async {
              created.add(name);
              return 'new-id';
            },
            sheetSemanticLabel: 'Authors',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('author-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('author-input')), typed);
    await tester.pumpAndSettle();
    return created;
  }

  testWidgets('a decomposed spelling of a live name offers no create', (
    tester,
  ) async {
    // Precondition: the two strings really are canonically equivalent and not
    // byte-equal, or the test passes without exercising anything.
    expect(_nfcCafe == _nfdCafe, isFalse);
    expect(_nfcCafe.toLowerCase() == _nfdCafe.toLowerCase(), isFalse);

    await pumpAndType(
      tester,
      _nfdCafe,
      options: const [(id: 'c1', name: _nfcCafe)],
    );

    expect(
      find.byKey(ValueKey('author-option-create:$_nfdCafe')),
      findsNothing,
      reason: 'the repository would refuse this create',
    );
    expect(
      find.byKey(const ValueKey('author-option-c1')),
      findsOneWidget,
      reason: 'the incumbent must still be offered, or there is no way forward',
    );
  });

  testWidgets('a genuinely new name still offers create', (tester) async {
    // The other side of the guard: a comparison widened until it matches
    // everything would pass the test above and break the picker.
    await pumpAndType(
      tester,
      'Brand New Author',
      options: const [(id: 'c1', name: _nfcCafe)],
    );
    expect(
      find.byKey(const ValueKey('author-option-create:Brand New Author')),
      findsOneWidget,
    );
  });

  testWidgets('case-only difference still offers no create, as before', (
    tester,
  ) async {
    // Pre-existing behaviour this change must not disturb: the picker was
    // already case-insensitive, and `naturalKeyMatchKey` keeps it so.
    await pumpAndType(
      tester,
      'GENE HUBERT',
      options: const [(id: 'gene', name: 'Gene Hubert')],
    );
    expect(
      find.byKey(const ValueKey('author-option-create:GENE HUBERT')),
      findsNothing,
    );
  });
}

// ---------------------------------------------------------------------------
// `onCreate` returning null is the one contract for "the create did not
// happen". `onAdd` must be skipped and the typed text kept, so the user can
// pick the row the create collided with; clearing the field would discard the
// name the snackbar is talking about.
//
// Pinned here rather than left incidental: the tag path shares this callback
// and never returns null today, so nothing else would notice if the skip were
// dropped.
void _createDeclinedGroup() {
  Future<List<String>> pumpAndTakeCreate(
    WidgetTester tester,
    String typed, {
    required Future<String?> Function(String) onCreate,
  }) async {
    final added = <String>[];
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: NamePicker(
            fieldKey: 'author',
            selectedIds: const [],
            namesById: const {},
            options: const [(id: 'gene', name: 'Gene Hubert')],
            onAdd: added.add,
            onRemove: (_) {},
            onCreate: onCreate,
            sheetSemanticLabel: 'Authors',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('author-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('author-input')), typed);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('author-option-create:$typed')));
    await tester.pumpAndSettle();
    return added;
  }

  testWidgets('a null from onCreate adds nothing and keeps the typed text', (
    tester,
  ) async {
    var createCalls = 0;
    final added = await pumpAndTakeCreate(
      tester,
      'Refused Name',
      onCreate: (_) async {
        createCalls++;
        return null;
      },
    );

    expect(createCalls, 1, reason: 'the create really was attempted');
    expect(added, isEmpty, reason: 'nothing may be attached');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('author-input')))
          .controller
          ?.text,
      'Refused Name',
      reason: 'the field keeps the name the message is about',
    );
  });

  testWidgets('a non-null id still adds, so the skip is not unconditional', (
    tester,
  ) async {
    final added = await pumpAndTakeCreate(
      tester,
      'Accepted Name',
      onCreate: (_) async => 'minted-id',
    );
    expect(added, ['minted-id']);
  });
}

/// Hosts a [NamePicker] that owns its selection, as the editor does: a check
/// adds, an uncheck removes, and the picker is rebuilt with the new list.
class _Host extends StatefulWidget {
  const _Host({
    required this.options,
    this.initial = const [],
    this.onEdit,
    this.show,
  });

  final List<NameOption> options;
  final List<String> initial;
  final ValueChanged<String>? onEdit;

  /// When set, the picker is shown only while this is true.
  final ValueNotifier<bool>? show;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final List<String> selected = [...widget.initial];
  late final Map<String, String> names = {
    for (final o in widget.options) o.id: o.name,
  };
  late final List<NameOption> options = [...widget.options];

  @override
  Widget build(BuildContext context) {
    final picker = NamePicker(
      fieldKey: 'author',
      selectedIds: List.of(selected),
      namesById: Map.of(names),
      options: List.of(options),
      onAdd: (id) => setState(() => selected.add(id)),
      onRemove: (id) => setState(() => selected.remove(id)),
      onCreate: (name) async {
        final id = 'new-$name';
        setState(() {
          names[id] = name;
          options.add((id: id, name: name));
        });
        return id;
      },
      onEdit: widget.onEdit,
      sheetSemanticLabel: 'Authors',
    );
    final show = widget.show;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (show == null)
            picker
          else
            ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) =>
                  visible ? picker : const SizedBox.shrink(),
            ),
          Text('chosen: ${selected.join('|')}', key: const ValueKey('chosen')),
        ],
      ),
    );
  }
}

void _dropDownGroup() {
  const people = [
    (id: 'zoe', name: 'Zoe Adams'),
    (id: 'amy', name: 'Amy Brown'),
    (id: 'max', name: 'Max Cole'),
  ];

  Future<void> pumpHost(
    WidgetTester tester, {
    List<String> initial = const [],
    ValueChanged<String>? onEdit,
    ValueNotifier<bool>? show,
  }) async {
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: _Host(
            options: people,
            initial: initial,
            onEdit: onEdit,
            show: show,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String chosen(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('chosen'))).data!;

  String fieldText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('author-names'))).data!;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('author-field')));
    await tester.pumpAndSettle();
  }

  bool checked(WidgetTester tester, String id) => tester
      .widget<CheckboxListTile>(find.byKey(ValueKey('author-option-$id')))
      .value!;

  testWidgets('the closed field reads the chosen names, with no chips', (
    tester,
  ) async {
    await pumpHost(tester, initial: ['max', 'zoe']);

    expect(fieldText(tester), 'Max Cole, Zoe Adams');
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    // Nothing is listed until the field is opened.
    expect(find.byKey(const ValueKey('author-option-amy')), findsNothing);
  });

  testWidgets('names stored family name first are set apart with '
      'semicolons (pre-release audit finding A2-06)', (tester) async {
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: NamePicker(
            fieldKey: 'author',
            selectedIds: const ['cs', 'ps'],
            namesById: const {'cs': 'Sharp, Cecil', 'ps': 'Shaw, Pat'},
            options: const [
              (id: 'cs', name: 'Sharp, Cecil'),
              (id: 'ps', name: 'Shaw, Pat'),
            ],
            onAdd: (_) {},
            onRemove: (_) {},
            onCreate: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Sharp, Cecil; Shaw, Pat');
  });

  testWidgets('an empty field shows the Choose hint', (tester) async {
    await pumpHost(tester);
    expect(fieldText(tester), isEmpty);
    expect(find.text('Choose…'), findsOneWidget);
  });

  testWidgets('on a wide window the list drops down under the field, lists '
      'the chosen names first then everyone by name, and checks the chosen', (
    tester,
  ) async {
    await pumpHost(tester, initial: ['max']);
    await open(tester);

    expect(find.byType(BottomSheet), findsNothing);
    final field = tester.getRect(find.byKey(const ValueKey('author-field')));
    final search = tester.getRect(find.byKey(const ValueKey('author-input')));
    expect(search.top, greaterThanOrEqualTo(field.bottom));

    double top(String id) =>
        tester.getRect(find.byKey(ValueKey('author-option-$id'))).top;
    // The options arrive as Zoe, Amy, Max: the chosen Max comes first, then
    // the rest by name.
    expect(top('max'), lessThan(top('amy')));
    expect(top('amy'), lessThan(top('zoe')));
    expect(checked(tester, 'max'), isTrue);
    expect(checked(tester, 'amy'), isFalse);
  });

  testWidgets('checking and unchecking rows adds and removes, the rows stay '
      'put, and the field follows', (tester) async {
    await pumpHost(tester);
    await open(tester);
    final before = tester
        .getRect(find.byKey(const ValueKey('author-option-max')))
        .top;

    await tester.tap(find.byKey(const ValueKey('author-option-max')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('author-option-amy')));
    await tester.pumpAndSettle();
    expect(chosen(tester), 'chosen: max|amy');
    expect(checked(tester, 'max'), isTrue);
    expect(checked(tester, 'amy'), isTrue);
    expect(
      tester.getRect(find.byKey(const ValueKey('author-option-max'))).top,
      before,
    );

    await tester.tap(find.byKey(const ValueKey('author-option-max')));
    await tester.pumpAndSettle();
    expect(chosen(tester), 'chosen: amy');
    expect(checked(tester, 'max'), isFalse);

    await tester.tap(find.byKey(const ValueKey('author-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('author-input')), findsNothing);
    expect(fieldText(tester), 'Amy Brown');
  });

  testWidgets('typing narrows the list, and Enter checks the first match '
      'and clears the search', (tester) async {
    await pumpHost(tester);
    await open(tester);

    await tester.enterText(find.byKey(const ValueKey('author-input')), 'co');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('author-option-max')), findsOneWidget);
    expect(find.byKey(const ValueKey('author-option-zoe')), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen(tester), 'chosen: max');
    final search = tester.widget<TextField>(
      find.byKey(const ValueKey('author-input')),
    );
    expect(search.controller!.text, isEmpty);
    expect(search.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Enter on a name nobody has creates it and checks it', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('author-input')),
      'Pat Shaw',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(chosen(tester), 'chosen: new-Pat Shaw');
    expect(checked(tester, 'new-Pat Shaw'), isTrue);
  });

  testWidgets('Enter skips a match already chosen and checks the next', (
    tester,
  ) async {
    await pumpHost(tester, initial: ['amy']);
    await open(tester);

    // "a" matches Amy (chosen, listed first), then Max Cole and Zoe Adams.
    await tester.enterText(find.byKey(const ValueKey('author-input')), 'a');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen(tester), 'chosen: amy|max');
  });

  testWidgets('Enter with only chosen matches adds nothing and keeps the '
      'typed text', (tester) async {
    await pumpHost(tester, initial: ['amy']);
    await open(tester);

    // The whole name, so no Create row is offered either.
    await tester.enterText(
      find.byKey(const ValueKey('author-input')),
      'Amy Brown',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen(tester), 'chosen: amy');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('author-input')))
          .controller!
          .text,
      'Amy Brown',
    );
  });

  testWidgets('closing the list gives focus back to the field, not to a '
      'text field that had it before', (tester) async {
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: ValueKey('other')),
              const _Host(options: people),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('author-done')));
    await tester.pumpAndSettle();

    final other = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('other')),
        matching: find.byType(EditableText),
      ),
    );
    expect(other.focusNode.hasFocus, isFalse);
  });

  testWidgets('in a right-to-left language the list lines up with the '
      "field's right edge", (tester) async {
    await setScreenSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            // A field narrower than the list, away from the window's edge,
            // so only its alignment decides where the list goes.
            body: Padding(
              padding: EdgeInsets.only(right: 400),
              child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(width: 232, child: _Host(options: people)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);

    final field = tester.getRect(find.byKey(const ValueKey('author-field')));
    final list = tester.getRect(find.byKey(const ValueKey('author-input')));
    // The search box sits inside the list's padding, at its right side.
    expect(list.right, closeTo(field.right - 16, 1));
  });

  testWidgets('a tap outside closes the list', (tester) async {
    await pumpHost(tester);
    await open(tester);
    await tester.tapAt(const Offset(1100, 850));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('author-input')), findsNothing);
  });

  testWidgets('the edit button closes the list and edits that person', (
    tester,
  ) async {
    final edited = <String>[];
    await pumpHost(tester, initial: ['amy'], onEdit: edited.add);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('author-edit-amy')));
    await tester.pumpAndSettle();

    expect(edited, ['amy']);
    expect(find.byKey(const ValueKey('author-input')), findsNothing);
  });

  testWidgets('the list closes when its field goes away', (tester) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await pumpHost(tester, show: show);
    await open(tester);

    show.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('author-input')), findsNothing);
  });

  testWidgets('screen readers hear the field name and the chosen names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHost(tester, initial: ['amy']);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('author-field'))),
      matchesSemantics(
        label: 'Authors',
        value: 'Amy Brown',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });
}
