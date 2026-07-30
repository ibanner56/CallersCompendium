import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/calling_history_caller_filter.dart';
import 'package:compendium_app/src/data/display_defaults.dart';

import '../support/test_repositories.dart';

/// Unit tests for the #583 decision tree encoded by
/// [resolveCallingHistoryCallerFilter].
void main() {
  late CompendiumRepositories repos;

  setUp(() async {
    repos = openTestRepositories();
    await repos.ensureMigrated();
  });

  Future<void> setDefaultCaller(String? value) async {
    if (value == null) return;
    await repos.settings.set(kDefaultProgramCallerKey, value);
  }

  test('track-all ON always yields null (track all callers)', () async {
    await setDefaultCaller('Alice');
    expect(
      await resolveCallingHistoryCallerFilter(
        repos.settings,
        trackAllCallers: true,
      ),
      isNull,
    );
  });

  test(
    'no default caller configured yields null even when track-all is OFF',
    () async {
      expect(
        await resolveCallingHistoryCallerFilter(
          repos.settings,
          trackAllCallers: false,
        ),
        isNull,
      );
    },
  );

  test('blank/whitespace default caller is treated as unset (null)', () async {
    await setDefaultCaller('   ');
    expect(
      await resolveCallingHistoryCallerFilter(
        repos.settings,
        trackAllCallers: false,
      ),
      isNull,
    );
  });

  test(
    'default caller set + track-all OFF yields the trimmed caller',
    () async {
      await setDefaultCaller('  Alice  ');
      expect(
        await resolveCallingHistoryCallerFilter(
          repos.settings,
          trackAllCallers: false,
        ),
        'Alice',
      );
    },
  );
}
