// In High contrast every menu carries an outline, the form dropdowns' included.
//
// The check is on what is painted: the opened menu's subtree must stroke a
// shape in the scheme's outline colour. A widget-type check would pass for a
// menu whose border is configured but never drawn.
import 'package:compendium_app/src/screens/dance_editor/editor_fields.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:compendium_app/src/widgets/settings_dropdown_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Pick { first, second, third }

/// A form field, as the dance editor's enum fields build it.
Widget _formField() => EnumDropdown<_Pick>(
  fieldKey: 'pick',
  label: 'Pick',
  value: _Pick.first,
  values: _Pick.values,
  labelOf: (v) => v.name,
  onChanged: (_) {},
);

/// A Settings row's trailing control, as every Settings dropdown row builds
/// it.
Widget _rowControl() => SettingsDropdownRow(
  title: const Text('Row'),
  dropdownBuilder: (expanded) => AppDropdownField<_Pick>(
    key: const ValueKey('pick-field'),
    compact: true,
    fillWidth: expanded,
    value: _Pick.first,
    entries: [
      for (final v in _Pick.values) AppDropdownEntry(value: v, label: v.name),
    ],
    onChanged: (_) {},
  ),
);

Future<void> _openRepresentativeField(
  WidgetTester tester,
  ThemeData theme, {
  Widget Function() field = _formField,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: field()),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('pick-field')));
  await tester.pumpAndSettle();
}

/// The open menu, found through the render tree so the check holds for any
/// menu implementation: [entries] is the smallest box holding two entries only
/// the open menu shows, and [layer] the highest box above it that does not
/// hold the field, which is everything the menu paints.
({RenderBox entries, RenderObject layer}) _openMenu(WidgetTester tester) {
  List<RenderObject> chain(RenderObject node) => [
    for (RenderObject? n = node; n != null; n = n.parent) n,
  ];
  final second = chain(tester.renderObject(find.text('second').last));
  final third = chain(tester.renderObject(find.text('third').last)).toSet();
  final entries = second.whereType<RenderBox>().firstWhere(third.contains);
  final field = chain(
    tester.renderObject(find.byKey(const ValueKey('pick-field'))),
  ).toSet();
  final above = chain(entries);
  final layer = above.lastWhere((n) => !field.contains(n));
  return (entries: entries, layer: layer);
}

/// The bounds a paint call covers, for the shapes a border is drawn with.
Rect? _boundsOf(Symbol method, List<dynamic> arguments) => switch (method) {
  #drawRRect => (arguments[0] as RRect).outerRect,
  #drawDRRect => (arguments[0] as RRect).outerRect,
  #drawRect => arguments[0] as Rect,
  #drawPath => (arguments[0] as Path).getBounds(),
  _ => null,
};

/// Whether a paint call draws a ring in [color] around at least [size]: the
/// menu's border, not the outline of one entry inside it.
bool _outlinesPanel(
  Size size,
  Color color,
  Symbol method,
  List<dynamic> arguments,
) {
  final bounds = _boundsOf(method, arguments);
  if (bounds == null) return false;
  final paint = arguments.whereType<Paint>().firstOrNull;
  // Compared as 32-bit ARGB: the painted colour can be a different Color
  // instance (or subtype) from the scheme's, which == treats as unequal.
  if (paint == null || paint.color.toARGB32() != color.toARGB32()) {
    return false;
  }
  final ring = paint.style == PaintingStyle.stroke || method == #drawDRRect;
  return ring && bounds.width >= size.width && bounds.height >= size.height;
}

void main() {
  testWidgets('High contrast paints an outline around an open form dropdown '
      'menu', (tester) async {
    final theme = AppTheme.highContrast;
    await _openRepresentativeField(tester, theme);
    final menu = _openMenu(tester);
    final size = menu.entries.size;
    // Taller than one entry, so an entry's own outline cannot pass for it.
    expect(size.height, greaterThan(80));
    expect(
      menu.layer,
      paints..something(
        (method, args) =>
            _outlinesPanel(size, theme.colorScheme.outline, method, args),
      ),
    );
  });

  testWidgets('the light theme keeps the menu tonal, with no outline', (
    tester,
  ) async {
    final theme = AppTheme.light;
    await _openRepresentativeField(tester, theme);
    final menu = _openMenu(tester);
    final size = menu.entries.size;
    expect(
      menu.layer,
      isNot(
        paints..something(
          (method, args) =>
              _outlinesPanel(size, theme.colorScheme.outline, method, args),
        ),
      ),
    );
  });

  testWidgets('High contrast paints an outline around the open menu of a '
      "Settings row's dropdown", (tester) async {
    final theme = AppTheme.highContrast;
    await _openRepresentativeField(tester, theme, field: _rowControl);
    final menu = _openMenu(tester);
    final size = menu.entries.size;
    expect(size.height, greaterThan(80));
    expect(
      menu.layer,
      paints..something(
        (method, args) =>
            _outlinesPanel(size, theme.colorScheme.outline, method, args),
      ),
    );
  });
}
