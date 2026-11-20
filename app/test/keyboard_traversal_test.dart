// Keyboard-only navigation of the core flows (`docs/dev/release-checklist.md`
// §7, "Keyboard-only navigation (desktop)"), run against the real app.
//
// The checklist's pass criteria are: every interactive element is reachable by
// Tab, has a visible focus indicator at every step, and there is no keyboard
// trap. Each screen here is walked with real Tab key events and checked three
// ways:
//
//  1. No trap: Tab wraps round the page within a bounded number of presses. A
//     repeat of a stop is the page wrapping round unless its loop is only a few
//     controls (under 5), which is a trap, wherever on the page it is. A trap
//     of five or more controls inside a long lazy form cannot be told from a
//     wrap this way (a lazy list's wrap lands on the first control still built,
//     not the first stop); the reachability and Shift+Tab checks below are what
//     would notice one. Shift+Tab, pressed as often, visits nearly as many
//     distinct stops as Tab did (it is not compared stop for stop: see the note
//     where it is checked).
//  2. Reachable: every tappable, enabled semantics node on screen is covered by
//     a Tab stop of about its own size (a stop for a small button inside a large
//     row does not count as reaching the row).
//  3. Visible: the app draws its focus ring from one layer (`FocusRingLayer`)
//     around whatever has keyboard focus, so after each Tab press the ring must
//     be there and must sit on the stop. Text fields draw their own border and
//     are exempt, as the layer exempts them. This reads the layer's own
//     rectangle; it does not measure the ring's contrast, which
//     `palette_contrast_test.dart` holds, and it cannot tell a ring drawn on the
//     wrong widget from a right one beyond its bounds. A pixel comparison was
//     tried first and does not work: in a widget test Material's focus and hover
//     overlays do not appear in a captured image, a press splash does.
//
// This supplements the manual gate; it does not replace it. It does not check
// the activation keys (Enter, Space), contrast, or text fields' own editing.
import 'dart:ui' as ui;

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/widgets/focus_ring_layer.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_wakelock.dart';
import 'support/full_app_harness.dart';
import 'support/real_fonts.dart';

/// A desktop window: the checklist's keyboard gate is a desktop gate.
const _desktop = Size(1100, 800);

/// A repeat is a trap, not the page wrapping round, when its loop is fewer than
/// this many stops, or fewer than this many were walked at all (a control that
/// swallows Tab on the first press repeats at once).
const _minLoop = 5;

/// The smallest a Tab stop may be on a side, in logical px. The smallest real
/// control here is a 24 px tap target.
const _minStop = 8.0;

/// More Tab presses than any screen here has stops. A screen that does not come
/// back to its first stop in this many is reported as a trap, not walked on.
const _maxStops = 120;

class _Stop {
  _Stop(
    this.node,
    this.rect,
    this.ring, {
    required this.isTextInput,
    this.describe = '',
  });
  final FocusNode node;
  final Rect rect;

  /// Where the focus ring layer drew its ring when this stop took focus.
  final Rect? ring;
  final bool isTextInput;

  /// What the stop is, for a failure message: its nearest keyed or labelled
  /// ancestors, read when the stop is recorded (the widget may be gone later).
  final String describe;

  /// A page-level node that exists only to receive keyboard shortcuts. The ring
  /// layer draws no ring on these (a ring round the whole page says nothing),
  /// by the same area share, so neither does this check count them as stops.
  bool get isWholeWindow =>
      rect.width * rect.height >
      _desktop.width * _desktop.height * FocusRingLayer.maxAreaShare;
}

Future<AppData> _seed() async {
  final appData = openTestAppData();
  final repos = appData.repositories;
  final stamp = DateTime.utc(2026, 1, 1);
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'c1', name: 'Gene Hubert'),
  );
  for (final (id, title) in [('d1', 'Petronella'), ('d2', 'The Baby Rose')]) {
    await repos.dances.create(
      Dance(
        id: id,
        title: title,
        authorIds: const ['c1'],
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
  }
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Autumn Ball',
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  return appData;
}

/// Whether [node]'s widget is still in the tree. A lazy list disposes an item
/// when it scrolls away, and the walk can be holding its node by then.
bool _live(FocusNode node) => node.context != null && node.context!.mounted;

String _describe(FocusNode node) {
  final parts = <String>[];
  node.context?.visitAncestorElements((e) {
    final w = e.widget;
    if (w.key is ValueKey) parts.add('key=${(w.key! as ValueKey).value}');
    if (w is Tooltip && w.message != null) parts.add('tooltip=${w.message}');
    if (w is Text && w.data != null) parts.add('text=${w.data}');
    return parts.length < 3;
  });
  return parts.join(' ');
}

Rect _globalRect(FocusNode node) {
  final box = node.context!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  // Long enough for a focus highlight's fade and a scroll into view to finish.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

class _Tappable {
  _Tappable(
    this.id,
    this.label,
    this.rect,
    this.kinds, {
    required this.hasFocus,
  });
  final int id;

  /// Whether the semantics tree says this node holds keyboard focus right now.
  /// Flutter reports it for the merged node of a control with a focusable
  /// inside, such as a settings row around a dropdown, whose Tab stop is the
  /// dropdown and not the whole row.
  final bool hasFocus;
  final String label;
  final Rect rect;
  final Set<String> kinds;
}

/// Every enabled node on screen that a pointer can tap, with its global rect.
/// [_Tappable.id] is the semantics node's, which stays the same for as long as
/// the widget does, so a list that scrolls under the walk can be followed.
List<_Tappable> _tappables(WidgetTester tester) {
  final found = <_Tappable>[];
  void walk(SemanticsNode node, Matrix4 parent) {
    final matrix = node.transform == null
        ? parent
        : parent.multiplied(node.transform!);
    final data = node.getSemanticsData();
    final rect = MatrixUtils.transformRect(matrix, node.rect);
    if (data.hasAction(SemanticsAction.tap) &&
        !node.isInvisible &&
        data.flagsCollection.isEnabled != ui.Tristate.isFalse &&
        rect.width > 0 &&
        rect.height > 0 &&
        rect.overlaps(Offset.zero & _desktop)) {
      final f = data.flagsCollection;
      final label = data.label.isNotEmpty
          ? data.label.replaceAll('\n', ' ')
          : data.tooltip;
      found.add(
        _Tappable(node.id, label.isEmpty ? '(unlabelled)' : label, rect, {
          if (f.isTextField) 'textfield',
          if (f.isButton) 'button',
          if (f.isChecked != ui.CheckedState.none) 'checkable',
          if (f.isToggled != ui.Tristate.none) 'toggle',
        }, hasFocus: f.isFocused == ui.Tristate.isTrue),
      );
    }
    node.visitChildren((child) {
      walk(child, matrix);
      return true;
    });
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
    Matrix4.identity(),
  );
  return found;
}

/// Whether a Tab stop at [stop] reaches [target]. Usually the two are about the
/// same size. Two shapes are not: a text field's stop is its editable area,
/// inside the field's own box; and a checkbox or switch inside a tile is
/// reached through the tile, which is the larger stop. A stop for a small button
/// inside a large row does not count as reaching the row.
bool _reaches(_Stop stopNode, _Tappable target) {
  final stop = stopNode.rect;
  final rect = target.rect;
  // A dropdown's arrow, to the right of its text field. On a desktop the field
  // is the one stop and the arrow is part of it, not a second Tab stop
  // (`AppDropdownField`), and the keyboard opens the menu from the field.
  if (stopNode.isTextInput &&
      target.label == '(unlabelled)' &&
      target.kinds.length == 1 &&
      target.kinds.contains('button') &&
      rect.left >= stop.right - 2 &&
      rect.left - stop.right <= 24 &&
      rect.top < stop.bottom &&
      rect.bottom > stop.top) {
    return true;
  }
  if (target.kinds.contains('textfield') &&
      rect.inflate(2).contains(stop.topLeft) &&
      rect.inflate(2).contains(stop.bottomRight)) {
    return true;
  }
  if ((target.kinds.contains('checkable') || target.kinds.contains('toggle')) &&
      stop.inflate(2).contains(rect.topLeft) &&
      stop.inflate(2).contains(rect.bottomRight)) {
    return true;
  }
  final overlap = stop.intersect(rect);
  if (overlap.width <= 0 || overlap.height <= 0) return false;
  final overlapArea = overlap.width * overlap.height;
  final stopArea = stop.width * stop.height;
  final targetArea = rect.width * rect.height;
  final union = stopArea + targetArea - overlapArea;
  return overlapArea / union >= 0.25 ||
      (overlapArea >= 0.8 * stopArea && stopArea >= 0.5 * targetArea);
}

/// What a walk found: the stops, and every tappable seen on screen along the
/// way that no stop reached.
typedef _Walk = ({
  List<_Stop> stops,
  List<String> unreached,

  /// The stops of a loop that is too small to be the page going round, or a
  /// note that Tab visited too few stops to have wrapped: a keyboard trap.
  /// `null` when Tab wrapped round the page.
  List<String>? trap,
});

/// Tab from a fresh start until a stop repeats, which is the page wrapping round
/// unless its loop is only a few stops, which is a trap. `null` means no repeat
/// within [_maxStops], that is, an unbounded traversal.
///
/// On a lazy list the controls scrolled far above are no longer built when Tab
/// wraps, so it lands on the first control still built, not on the first stop;
/// that is why a wrap is judged by the size of its loop, not by where it ends.
///
/// A lazy list scrolls and builds as focus moves, so what is tappable changes
/// from step to step. Each step therefore asks which of the tappables on screen
/// *now* the stop reaches, and a tappable counts as unreached only if it was on
/// screen at some step and no step reached it.
Future<_Walk?> _walk(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final stops = <_Stop>[];
  final seen = <int, String>{};
  final reached = <int>{};
  for (var i = 0; i < _maxStops; i++) {
    await _tab(tester);
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !_live(node)) continue;
    final repeat = stops.indexWhere((s) => identical(s.node, node));
    if (repeat >= 0) {
      final loop = stops.length - repeat;
      return (
        stops: stops,
        unreached: [
          for (final e in seen.entries)
            if (!reached.contains(e.key)) e.value,
        ],
        trap: loop >= _minLoop && stops.length >= _minLoop
            ? null
            : [
                if (stops.length < _minLoop)
                  'Tab came back after only ${stops.length} stop(s)',
                for (final s in stops.sublist(repeat))
                  '${s.rect} ${s.describe}',
              ],
      );
    }
    final stop = _Stop(
      node,
      _globalRect(node),
      tester.state<FocusRingLayerState>(find.byType(FocusRingLayer)).ringRect,
      isTextInput:
          node.context!.findAncestorWidgetOfExactType<EditableText>() != null,
      describe: _describe(node),
    );
    stops.add(stop);
    if (stop.isWholeWindow) continue;
    for (final t in _tappables(tester)) {
      seen[t.id] = '${t.label} [${t.kinds.join('+')}] ${t.rect}';
      if (t.hasFocus || _reaches(stop, t)) reached.add(t.id);
    }
  }
  return null;
}

/// Whether the ring was drawn on [stop]: the layer measures the widget's own
/// bounds, so they agree to within rounding.
bool _sameBounds(Rect ring, Rect stop) =>
    (ring.left - stop.left).abs() < 1 &&
    (ring.top - stop.top).abs() < 1 &&
    (ring.width - stop.width).abs() < 1 &&
    (ring.height - stop.height).abs() < 1;

/// Pumps the full app, runs [navigate] to reach a screen, then walks it.
void _screen(
  String name,
  Future<void> Function(WidgetTester tester) navigate, {
  required Finder landedOn,
  List<String> mustStopAt = const [],
}) {
  testWidgets(name, (tester) async {
    await loadBundledFonts();
    installFakeWakelock();
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final appData = await _seed();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _desktop;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();
      await navigate(tester);
      expect(tester.takeException(), isNull, reason: 'navigating to $name');
      expect(landedOn, findsWidgets, reason: 'did not reach $name');

      // 1. No trap.
      final walk = await _walk(tester);
      expect(
        walk,
        isNotNull,
        reason:
            '$name: Tab did not come back to its first stop in $_maxStops presses',
      );
      expect(
        walk!.trap,
        isNull,
        reason: '$name: Tab is stuck in a loop of a few controls',
      );
      final stops = walk.stops;
      final real = stops.where((s) => !s.isWholeWindow).toList();
      expect(real, isNotEmpty, reason: '$name: Tab reached no control at all');
      // Shift+Tab must not trap either: pressed twice as often as Tab was, it
      // visits nearly as many distinct stops (80%). Not the same nodes, nor
      // quite the same count: a lazy list builds a new node each time an item
      // scrolls back in, and a form's group nodes recur inside the loop. A trap
      // shows as a handful of nodes visited over and over.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final reversed = <FocusNode>{};
      for (var i = 0; i < stops.length * 2; i++) {
        await _tab(tester, shift: true);
        final node = FocusManager.instance.primaryFocus;
        if (node != null &&
            _live(node) &&
            !_Stop(
              node,
              _globalRect(node),
              null,
              isTextInput: false,
            ).isWholeWindow) {
          reversed.add(node);
        }
      }
      expect(
        reversed.length,
        greaterThanOrEqualTo((real.length * 0.8).ceil()),
        reason:
            '$name: Shift+Tab visited ${reversed.length} distinct stops where '
            'Tab visited ${real.length}',
      );

      // Controls a lazy list never scrolls to are never on screen to be judged
      // below, so a screen can name the ones that must be Tab stops.
      for (final key in mustStopAt) {
        expect(
          real.any((s) => s.describe.contains('key=$key')),
          isTrue,
          reason: '$name: no Tab stop on $key',
        );
      }

      // 2. Everything tappable is reachable.
      expect(
        walk.unreached,
        isEmpty,
        reason: '$name: tappable but never reached by Tab',
      );

      // A stop must be somewhere a person can see it. The ring check compares
      // the ring with the stop's own bounds, so a zero-size or off-screen stop
      // would otherwise pass it.
      expect(
        [
          for (final stop in real)
            if (stop.rect.width < _minStop ||
                stop.rect.height < _minStop ||
                !(Offset.zero & _desktop).contains(stop.rect.center))
              '${stop.rect} ${stop.describe}',
        ],
        isEmpty,
        reason: '$name: a Tab stop that is tiny or off screen',
      );

      // 3. Every stop shows the focus ring (text fields draw their own).
      final noRing = [
        for (final stop in real)
          if (!stop.isTextInput &&
              (stop.ring == null || !_sameBounds(stop.ring!, stop.rect)))
            '${stop.rect} ring=${stop.ring} ${stop.describe}',
      ];
      expect(noRing, isEmpty, reason: '$name: a stop with no focus ring on it');
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Scrolls the lazy form to the expansion tile with [key] and opens it.
Future<void> _openTile(
  WidgetTester tester,
  String key, {
  required String field,
}) async {
  final tile = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    tile,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
  // Guards against walking a tile that did not open.
  expect(
    find.byKey(ValueKey(field)),
    findsWidgets,
    reason: '$key did not open',
  );
  // Back to the top: Tab from nothing starts at the page's first control, and
  // would begin above the visible area if the page were left scrolled down.
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _openProgramSummary(WidgetTester tester) async {
  await tester.tap(find.text('Programs').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Autumn Ball'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _screen('Collection', (_) async {}, landedOn: find.text('Petronella'));

  _screen('Dance detail', (tester) async {
    await tester.tap(find.text('Petronella'));
    await tester.pumpAndSettle();
  }, landedOn: find.byType(DanceDetailScreen));

  _screen('Dance editor', (tester) async {
    await _tapKey(tester, 'new-dance');
  }, landedOn: find.byType(DanceEditorScreen));

  // The editors' "More details" section keeps its fields built while collapsed,
  // so it is walked open as well: its fields must join the focus order then, and
  // its dropdowns must take focus (they read their node's focusability when
  // built).
  _screen(
    'Dance editor, More details open',
    (tester) async {
      await _tapKey(tester, 'new-dance');
      await _openTile(tester, 'more-details-tile', field: 'mixed-level-field');
    },
    landedOn: find.byType(DanceEditorScreen),
    mustStopAt: ['status-field', 'mixed-level-field'],
  );

  _screen('Programs list', (tester) async {
    await tester.tap(find.text('Programs').last);
    await tester.pumpAndSettle();
  }, landedOn: find.byKey(const ValueKey('new-program')));

  _screen(
    'Program summary',
    _openProgramSummary,
    // On a desktop window the summary is a pane beside the list.
    landedOn: find.byKey(const ValueKey('summary-perform')),
  );

  _screen('Program builder', (tester) async {
    await _openProgramSummary(tester);
    await _tapKey(tester, 'open-builder');
  }, landedOn: find.byType(ProgramEditorScreen));

  _screen(
    'Program builder, More details open',
    (tester) async {
      await _openProgramSummary(tester);
      await _tapKey(tester, 'open-builder');
      await _openTile(
        tester,
        'program-more-details-tile',
        field: 'program-band',
      );
    },
    landedOn: find.byType(ProgramEditorScreen),
    mustStopAt: ['program-band'],
  );

  _screen('Perform', (tester) async {
    await _openProgramSummary(tester);
    await _tapKey(tester, 'summary-perform');
  }, landedOn: find.byType(PerformProgramScreen));

  // On a desktop window Settings is a sidebar beside the section's content.
  _screen('Settings', (tester) async {
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
  }, landedOn: find.byKey(const ValueKey('settings-nav-general')));
}
