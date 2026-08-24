import 'package:compendium_app/src/app_metadata.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const releaseBuildVersion = String.fromEnvironment(
    'CALLERS_COMPENDIUM_RELEASE_VERSION',
  );

  test('the updater identity follows the release-build seam', () {
    expect(
      kUpdaterVersion,
      releaseBuildVersion.isEmpty ? kAppVersion : releaseBuildVersion,
    );
    expect(SemVer.tryParse(kUpdaterVersion), isNotNull);
  });
}
