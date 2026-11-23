import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the dropdown [field] (an `AppDropdownField`, or anything that opens
/// a `DropdownMenu` on tap) and picks the entry labelled [label], each with a
/// [press]: a mouse click on a desktop, a touch elsewhere.
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
  await press(tester, field);
  await tester.pumpAndSettle();
  final entry = dropdownEntry(label);
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await press(tester, entry);
  await tester.pumpAndSettle();
}

/// Presses [target] and lets a frame pass before releasing it, as a real
/// click or tap does; [kind] defaults to a mouse on a desktop platform and a
/// touch elsewhere.
///
/// `tester.tap` sends the press and the release with no frame between them,
/// so whatever the press sets off (a field losing focus, a menu closing) has
/// not yet been built when the release arrives, and the tap lands on what is
/// no longer there for a user. That hid #2292's menu that shut on a mouse
/// press before the click could pick.
///
/// Fails if something else is over [target]'s centre, so the press would
/// land on that instead.
Future<void> press(
  WidgetTester tester,
  Finder target, {
  PointerDeviceKind? kind,
}) async {
  final at = tester.getCenter(target);
  final hit = tester.hitTestOnBinding(at);
  final element = target.evaluate().single;
  expect(
    hit.path.any((entry) => entry.target == element.renderObject),
    isTrue,
    reason: 'a press at $at would not reach $target',
  );
  final gesture = await tester.createGesture(
    kind:
        kind ??
        switch (defaultTargetPlatform) {
          TargetPlatform.linux ||
          TargetPlatform.macOS ||
          TargetPlatform.windows => PointerDeviceKind.mouse,
          TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.fuchsia => PointerDeviceKind.touch,
        },
  );
  await gesture.down(at);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await gesture.removePointer();
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
