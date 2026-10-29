// Guards the venue sheet against closing over unsaved changes (UX2-1d): a tap
// above it, Back, and a swipe-down. A swipe pops the route directly, past
// `PopScope`, so the sheet must not be draggable at all.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/venue_editor_sheet.dart';

import '../support/l10n_harness.dart';

/// Opens [VenueEditorSheet] for [initial] and reports whether it has closed,
/// and with what.
Future<({bool closed, Venue? result}) Function()> _open(
  WidgetTester tester, {
  Venue? initial,
}) async {
  var closed = false;
  Venue? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await VenueEditorSheet.show(context, initial: initial);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => (closed: closed, result: result);
}

final _name = find.byKey(const ValueKey('venue-name-field'));
final _city = find.byKey(const ValueKey('venue-city-field'));

/// A point on the barrier, above the sheet.
const _aboveSheet = Offset(400, 10);

void main() {
  final hall = Venue(id: 'v1', name: 'Grange Hall', city: 'Easton');

  testWidgets('the sheet cannot be dragged and shows no drag handle', (
    tester,
  ) async {
    await _open(tester, initial: hall);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.enableDrag, isFalse);
    expect(sheet.showDragHandle ?? false, isFalse);
  });

  testWidgets('an untouched venue closes on a tap above it', (tester) async {
    final state = await _open(tester, initial: hall);
    await tester.tapAt(_aboveSheet);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(state().closed, isTrue);
  });

  testWidgets('an edited venue asks on a tap above it; Keep editing stays', (
    tester,
  ) async {
    final state = await _open(tester, initial: hall);
    await tester.enterText(_city, 'Weston');
    await tester.pump();
    await tester.tapAt(_aboveSheet);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('discard-cancel')));
    await tester.pumpAndSettle();
    expect(state().closed, isFalse);
    expect(find.text('Weston'), findsOneWidget);
  });

  testWidgets('an edited venue asks on Back; Discard closes with nothing', (
    tester,
  ) async {
    final state = await _open(tester, initial: hall);
    await tester.enterText(_city, 'Weston');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('discard-confirm')));
    await tester.pumpAndSettle();
    expect(state().closed, isTrue);
    expect(state().result, isNull);
  });

  testWidgets('a swipe down does not close an edited venue', (tester) async {
    final state = await _open(tester, initial: hall);
    await tester.enterText(_city, 'Weston');
    await tester.pump();
    await tester.fling(find.text('Edit venue'), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(state().closed, isFalse);
    expect(find.text('Weston'), findsOneWidget);
  });

  testWidgets('a new venue typed into asks before it is lost', (tester) async {
    final state = await _open(tester);
    await tester.enterText(_name, 'Town Hall');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(state().closed, isFalse);
  });

  testWidgets('Cancel closes an edited venue without asking', (tester) async {
    final state = await _open(tester, initial: hall);
    await tester.enterText(_city, 'Weston');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('venue-editor-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(state().closed, isTrue);
    expect(state().result, isNull);
  });
}
