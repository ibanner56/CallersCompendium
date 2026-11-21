import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/dance_share_fields_scope.dart';

void main() {
  group('decodeStored (issue #1434) — mirrors CollectionTileFieldsScope', () {
    test('a non-List value (absent/corrupt) falls back to allExceptTunes', () {
      expect(
        DanceShareFieldsScope.decodeStored(null),
        DanceShareField.allExceptTunes,
      );
      expect(
        DanceShareFieldsScope.decodeStored('authors'),
        DanceShareField.allExceptTunes,
      );
      expect(
        DanceShareFieldsScope.decodeStored(7),
        DanceShareField.allExceptTunes,
      );
      expect(
        DanceShareFieldsScope.decodeStored(<String, Object?>{'a': 1}),
        DanceShareField.allExceptTunes,
      );
    });

    test('an empty List means the user deliberately turned everything off', () {
      expect(DanceShareFieldsScope.decodeStored(<dynamic>[]), isEmpty);
    });

    test('a non-empty List decodes recognised names, drops the rest', () {
      expect(
        DanceShareFieldsScope.decodeStored(<dynamic>[
          'authors',
          'tunes',
          1,
          null,
        ]),
        {DanceShareField.authors, DanceShareField.tunes},
      );
    });

    test('a List of only unrecognised names falls back to allExceptTunes '
        '(open-world forward compat)', () {
      expect(
        DanceShareFieldsScope.decodeStored(<dynamic>['some-future-field']),
        DanceShareField.allExceptTunes,
      );
    });
  });

  testWidgets('of() returns allExceptTunes when no scope is mounted', (
    tester,
  ) async {
    late Set<DanceShareField> seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = DanceShareFieldsScope.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(seen, DanceShareField.allExceptTunes);
  });

  testWidgets('of() tracks the notifier and notifierOf() throws without one', (
    tester,
  ) async {
    final notifier = ValueNotifier<Set<DanceShareField>>(
      DanceShareField.allExceptTunes,
    );
    addTearDown(notifier.dispose);
    var builds = 0;
    late Set<DanceShareField> seen;
    await tester.pumpWidget(
      DanceShareFieldsScope(
        notifier: notifier,
        child: Builder(
          builder: (context) {
            builds++;
            seen = DanceShareFieldsScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, DanceShareField.allExceptTunes);

    notifier.value = {DanceShareField.authors};
    await tester.pump();
    expect(seen, {DanceShareField.authors});
    expect(builds, 2);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(
            () => DanceShareFieldsScope.notifierOf(context),
            throwsFlutterError,
          );
          return const SizedBox();
        },
      ),
    );
  });
}
