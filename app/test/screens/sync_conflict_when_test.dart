import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/screens/sync_conflict_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The date a sync conflict shows for "changed at" follows the Regional date
/// setting, as event dates do, rather than a month name in the app's language.
void main() {
  testWidgets('syncConflictWhen follows the chosen date format', (
    tester,
  ) async {
    final setting = ValueNotifier(DateFormatSetting(DateFormatPref.ymd));
    addTearDown(setting.dispose);
    late String shown;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DateFormatScope(
          notifier: setting,
          child: Builder(
            builder: (context) {
              shown = syncConflictWhen(context, DateTime(2026, 7, 15, 15, 4));
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(shown, startsWith('2026-07-15 '));
  });
}
