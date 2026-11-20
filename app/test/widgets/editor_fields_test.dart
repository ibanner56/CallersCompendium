import 'package:compendium_app/src/screens/dance_editor/editor_fields.dart';
import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dropdown.dart';
import '../support/l10n_harness.dart';

/// Reads the value the field's own [FormFieldState] is holding — the exact
/// thing the removed comment claimed does not update.
T? _fieldValue<T>(WidgetTester tester) =>
    tester.state<FormFieldState<T>>(findDropdown<T>()).value;

/// Pumps [build] under a host that owns the model the way the dance editor
/// does: the widget reports through `onChanged`, the host stores it, and the
/// returned setter mutates the model from OUTSIDE — the shape of an undo, a
/// redo, or a draft restore. Nothing here rebuilds the subtree by identity, so
/// a stable key has to carry the resync on its own.
Future<StateSetter> _pumpExternallyDriven(
  WidgetTester tester,
  Widget Function(StateSetter setState) build,
) async {
  late StateSetter setOuter;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return build(setState);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return setOuter;
}

void main() {
  // Issue #775. `EnumDropdown` once carried a value-based key justified by the
  // claim that its dropdown "does not re-initialize its state from its value
  // after construction". The app's dropdown, `AppDropdownField`, re-reads its
  // value in `didUpdateWidget`, as the field it replaced did. Plain `FormField`
  // is what does not — it syncs only `forceErrorText` (`widgets/form.dart`) —
  // which is the likely source of the confusion.
  //
  // This is the measurement the rest of the file relies on, on the shared
  // field alone: if it regresses, every guard below fails too, and this test
  // says why in one place.
  testWidgets('a stable-keyed AppDropdownField follows a later value', (
    tester,
  ) async {
    String? current = 'a';
    final setModel = await _pumpExternallyDriven(
      tester,
      (setState) => AppDropdownField<String?>(
        // Stable — nothing here varies with the value.
        key: const ValueKey('measurement-dropdown'),
        value: current,
        decoration: const InputDecoration(hintText: 'HINT'),
        entries: const [
          AppDropdownEntry(value: 'a', label: 'Alpha'),
          AppDropdownEntry(value: 'b', label: 'Bravo'),
        ],
        onChanged: (v) => setState(() => current = v),
      ),
    );
    final field = find.byKey(const ValueKey('measurement-dropdown'));
    expect(_fieldValue<String?>(tester), 'a', reason: 'initial state');
    expect(dropdownShown(tester, field), 'Alpha');

    // 'a' -> 'b', changed from OUTSIDE the dropdown, key unchanged.
    setModel(() => current = 'b');
    await tester.pumpAndSettle();
    expect(_fieldValue<String?>(tester), 'b');
    expect(dropdownShown(tester, field), 'Bravo');

    // 'b' -> null: the selection drops and the hint comes back.
    setModel(() => current = null);
    await tester.pumpAndSettle();
    expect(_fieldValue<String?>(tester), isNull);
    expect(dropdownShown(tester, field), isEmpty);
    expect(find.text('HINT'), findsOneWidget);
  });

  // The guards below pin what the deleted comments claimed, for the widgets
  // that carried them. They are what makes the claim checkable now that it is
  // no longer asserted in prose.
  group('external resync —', () {
    testWidgets('EnumDropdown follows a value changed by the parent', (
      tester,
    ) async {
      var progression = Progression.none;
      final setModel = await _pumpExternallyDriven(
        tester,
        (setState) => EnumDropdown<Progression>(
          fieldKey: 'progression',
          label: 'Progression',
          value: progression,
          values: Progression.values,
          labelOf: (v) => v.name,
          onChanged: (v) => setState(() => progression = v),
        ),
      );
      expect(find.text(Progression.none.name).hitTestable(), findsOneWidget);

      setModel(() => progression = Progression.double);
      await tester.pumpAndSettle();
      expect(_fieldValue<Progression>(tester), Progression.double);
      expect(find.text(Progression.double.name).hitTestable(), findsOneWidget);
      expect(find.text(Progression.none.name).hitTestable(), findsNothing);
    });

    testWidgets('EnumDropdown still reports the user\'s own selection', (
      tester,
    ) async {
      // The resync path must not cost the ordinary one: the host writes back
      // what `onChanged` reports, so a broken round-trip shows up as a display
      // that snaps back.
      var status = DanceStatus.active;
      await _pumpExternallyDriven(
        tester,
        (setState) => EnumDropdown<DanceStatus>(
          fieldKey: 'status',
          label: 'Status',
          value: status,
          values: DanceStatus.values,
          labelOf: (v) => v.name,
          onChanged: (v) => setState(() => status = v),
        ),
      );

      await pickDropdownEntry(
        tester,
        findDropdown<DanceStatus>(),
        DanceStatus.broken.name,
      );

      expect(status, DanceStatus.broken);
      expect(_fieldValue<DanceStatus>(tester), DanceStatus.broken);
      expect(find.text(DanceStatus.broken.name).hitTestable(), findsOneWidget);
    });

    testWidgets('LevelDropdown follows a value changed by the parent', (
      tester,
    ) async {
      DanceLevel? level = DanceLevel.beginner;
      final setModel = await _pumpExternallyDriven(
        tester,
        (setState) => LevelDropdown(
          value: level,
          onChanged: (v) => setState(() => level = v),
        ),
      );
      expect(find.text('Beginner').hitTestable(), findsOneWidget);

      setModel(() => level = DanceLevel.advanced);
      await tester.pumpAndSettle();
      expect(_fieldValue<DanceLevel?>(tester), DanceLevel.advanced);
      expect(find.text('Advanced').hitTestable(), findsOneWidget);
      expect(find.text('Beginner').hitTestable(), findsNothing);
    });

    testWidgets('LevelDropdown follows a clear back to null', (tester) async {
      // The nullable transition is the one the bare-SDK measurement showed
      // behaves differently — the selection drops rather than being replaced —
      // and it is reachable in the app by undoing a level assignment.
      DanceLevel? level = DanceLevel.intermediate;
      final setModel = await _pumpExternallyDriven(
        tester,
        (setState) => LevelDropdown(
          value: level,
          onChanged: (v) => setState(() => level = v),
        ),
      );
      expect(find.text('Intermediate').hitTestable(), findsOneWidget);

      setModel(() => level = null);
      await tester.pumpAndSettle();
      expect(_fieldValue<DanceLevel?>(tester), isNull);
      expect(find.text('Intermediate').hitTestable(), findsNothing);
      // `null` is a real item here ("Unspecified"), not a hint, so it is
      // selected rather than falling back.
      expect(find.text('Unspecified').hitTestable(), findsOneWidget);
    });
  });
}
