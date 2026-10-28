import 'dart:io';

import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/diagnostics/crash_log_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus/share_plus.dart';

import '../support/test_repositories.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.temp);

  final String temp;

  @override
  Future<String?> getTemporaryPath() async => temp;
}

void main() {
  late Directory temp;
  late Future<ShareResult> Function(ShareParams) originalShare;
  late PathProviderPlatform originalPaths;
  late bool Function() originalDesktop;
  late bool Function() originalLogDesktop;

  var status = ShareResultStatus.dismissed;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('backup_share_result_test');
    originalShare = shareFilesViaSheet;
    shareFilesViaSheet = (_) async => ShareResult('', status);
    originalPaths = PathProviderPlatform.instance;
    originalDesktop = isDesktopPlatform;
    originalLogDesktop = isDesktopPlatformForLog;
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    isDesktopPlatform = () => false;
    isDesktopPlatformForLog = () => false;
  });

  tearDown(() {
    shareFilesViaSheet = originalShare;
    PathProviderPlatform.instance = originalPaths;
    isDesktopPlatform = originalDesktop;
    isDesktopPlatformForLog = originalLogDesktop;
    temp.deleteSync(recursive: true);
  });

  // `SharePlus.instance` captures `SharePlatform.instance` once, on first use,
  // so one fake is installed up front and its status switched per case.
  group('mobile share sheet result', () {
    for (final entry in {
      ShareResultStatus.dismissed: false,
      ShareResultStatus.success: true,
      ShareResultStatus.unavailable: true,
    }.entries) {
      test(
        '${entry.key.name}: saveBackupToFile returns ${entry.value}',
        () async {
          status = entry.key;
          expect(await saveBackupToFile('{}', 'b.json'), entry.value);
          expect(await saveDiagnosticsLog('log', 'l.txt'), entry.value);
        },
      );
    }
  });

  test('a dismissed share sheet does not stamp last_backup_at', () async {
    final repos = openTestRepositories();
    status = ShareResultStatus.dismissed;

    final delivered = await exportBackupNow(
      repos,
      saveBackupToFile,
      DateTime.utc(2026, 10, 28),
    );

    expect(delivered, isFalse);
    expect(await repos.settings.get(kLastBackupAtKey), isNull);
  });

  test('a completed share stamps last_backup_at', () async {
    final repos = openTestRepositories();
    status = ShareResultStatus.success;

    final delivered = await exportBackupNow(
      repos,
      saveBackupToFile,
      DateTime.utc(2026, 10, 28),
    );

    expect(delivered, isTrue);
    expect(await repos.settings.get(kLastBackupAtKey), isNotNull);
  });
}
