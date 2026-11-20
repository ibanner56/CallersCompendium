import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the dropdown [field] (an `AppDropdownField`, or anything that opens
/// a `DropdownMenu` on tap) and picks the entry labelled [label].
///
/// The open menu's entries are the only [MenuItemButton]s carrying the label,
/// so the closed field's own text (which may show the same label) is never
/// tapped by mistake.
Future<void> pickDropdownEntry(
  WidgetTester tester,
  Finder field,
  String label,
) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  final entry = dropdownEntry(label);
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

/// The open dropdown menu's entry labelled [label].
Finder dropdownEntry(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(MenuItemButton))
    .last;

/// The text an `AppDropdownField` (or `DropdownMenu`) found by [field] shows.
String dropdownShown(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// Opens the `AppDropdownField<T>` found by [field] and picks the entry whose
/// value is [value], whatever its (localized) label.
Future<void> pickDropdownValue<T>(
  WidgetTester tester,
  Finder field,
  T value,
) async {
  final widget = tester.widget<AppDropdownField<T>>(field);
  final entry = widget.entries.firstWhere((e) => e.value == value);
  await pickDropdownEntry(tester, field, entry.label);
}

/// Finds the `AppDropdownField<T>`s whose type argument is exactly [T].
Finder findDropdown<T>() => find.byType(AppDropdownField<T>);

/// Fails if the closed dropdown [field] cuts its value off: the closed field
/// cannot ellipsize, so a value wider than its text box is silently clipped.
/// Meaningful only with the real fonts loaded (`loadBundledFonts`).
void expectClosedValueFits(WidgetTester tester, Finder field) {
  final editable = tester.renderObject<RenderEditable>(
    find.descendant(
      of: field,
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_Editable',
      ),
    ),
  );
  expect(
    editable.size.width,
    greaterThanOrEqualTo(editable.getMaxIntrinsicWidth(double.infinity)),
    reason: dropdownShown(tester, field),
  );
}
