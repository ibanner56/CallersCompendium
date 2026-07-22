import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/choreographer_details_dialog.dart';

import '../support/l10n_harness.dart';

/// Pumps a button that opens [ChoreographerDetailsDialog] for [choreographer]
/// and returns a reader that settles and yields the dialog's result.
Future<Future<Choreographer?> Function()> _pumpDialog(
  WidgetTester tester,
  Choreographer choreographer,
) async {
  Choreographer? result;
  var completed = false;
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await ChoreographerDetailsDialog.show(
                context,
                choreographer,
              );
              completed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  return () async {
    await tester.pumpAndSettle();
    expect(completed, isTrue, reason: 'dialog did not close');
    return result;
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Choreographer?> openAndAct(
    WidgetTester tester,
    Choreographer choreographer,
    Future<void> Function() act,
  ) async {
    final read = await _pumpDialog(tester, choreographer);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act();
    return read();
  }

  testWidgets('prefills existing values', (tester) async {
    final c = Choreographer(
      id: 'c1',
      name: 'Gene Hubert',
      website: 'https://example.com',
      notes: 'A note',
      email: 'gene@example.com',
      location: 'Durham, NC',
      deceased: true,
    );
    await _pumpDialog(tester, c);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Gene Hubert'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text('A note'), findsOneWidget);
    expect(find.text('gene@example.com'), findsOneWidget);
    expect(find.text('Durham, NC'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('choreographer-deceased-toggle')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('has an accessible title and labelled fields', (tester) async {
    await _pumpDialog(tester, Choreographer(id: 'c1', name: 'Gene'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Choreographer details'), findsOneWidget);
    expect(find.text('Name *'), findsOneWidget);
    expect(find.text('Email (private)'), findsOneWidget);
    expect(find.text('Location (private)'), findsOneWidget);
    expect(find.text('Deceased'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Privacy / shared-entity helper copy.
    expect(find.textContaining('shared'), findsOneWidget);
    expect(find.textContaining('never shared or exported'), findsOneWidget);
  });

  testWidgets('saving returns updated email/location/deceased', (tester) async {
    final result = await openAndAct(
      tester,
      Choreographer(id: 'c1', name: 'Gene'),
      () async {
        await tester.enterText(
          find.byKey(const ValueKey('choreographer-email-field')),
          'gene@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey('choreographer-location-field')),
          'Durham, NC',
        );
        await tester.tap(
          find.byKey(const ValueKey('choreographer-deceased-toggle')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('choreographer-save')));
      },
    );

    expect(result, isNotNull);
    expect(result!.id, 'c1');
    expect(result.email, 'gene@example.com');
    expect(result.location, 'Durham, NC');
    expect(result.deceased, isTrue);
  });

  testWidgets('clearing email/location/website/notes persists null', (
    tester,
  ) async {
    final result = await openAndAct(
      tester,
      Choreographer(
        id: 'c1',
        name: 'Gene',
        website: 'https://old.example',
        notes: 'old notes',
        email: 'gene@example.com',
        location: 'Durham, NC',
      ),
      () async {
        await tester.enterText(
          find.byKey(const ValueKey('choreographer-email-field')),
          '   ',
        );
        await tester.enterText(
          find.byKey(const ValueKey('choreographer-location-field')),
          '',
        );
        await tester.enterText(
          find.byKey(const ValueKey('choreographer-website-field')),
          '',
        );
        await tester.enterText(
          find.byKey(const ValueKey('choreographer-notes-field')),
          '   ',
        );
        await tester.tap(find.byKey(const ValueKey('choreographer-save')));
      },
    );

    expect(result, isNotNull);
    expect(result!.email, isNull);
    expect(result.location, isNull);
    expect(result.website, isNull);
    expect(result.notes, isNull);
  });

  testWidgets('empty name blocks save', (tester) async {
    await _pumpDialog(tester, Choreographer(id: 'c1', name: 'Gene'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('choreographer-name-field')),
      '   ',
    );
    await tester.tap(find.byKey(const ValueKey('choreographer-save')));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    // Dialog stays open (still findable), so no result yet.
    expect(find.text('Choreographer details'), findsOneWidget);
  });

  testWidgets('cancel returns null', (tester) async {
    final result = await openAndAct(
      tester,
      Choreographer(id: 'c1', name: 'Gene'),
      () async {
        await tester.tap(find.byKey(const ValueKey('choreographer-cancel')));
      },
    );
    expect(result, isNull);
  });
}
