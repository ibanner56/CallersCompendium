import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'test_repositories.dart';

/// A [WindowService] whose restore is a no-op: the plugin glue is untestable
/// under `flutter test`, and full-app tests only care about the running app.
class NoopWindowService extends WindowService {
  NoopWindowService(super.settings);

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}
}

/// Opens an in-memory [AppData] for a full-app test.
AppData openTestAppData() {
  final appData = AppData(openWidgetTestDatabase(closeOnTearDown: false));
  // The database is also closed by CompendiumApp.dispose(); sqlite3's close is
  // idempotent, so this teardown just guarantees cleanup even for the last test
  // in the file (whose widget tree is never unmounted).
  addTearDown(appData.close);
  return appData;
}
