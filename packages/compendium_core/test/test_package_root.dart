import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Returns the absolute filesystem path of the `compendium_core` package root
/// (i.e. `packages/compendium_core/`), resolved via pub's package config.
///
/// This is CWD-independent: the resolution goes through the package URI that
/// `dart pub get` writes into `.dart_tool/package_config.json`, so the result
/// is the same whether `dart test` is invoked from the repo root or from inside
/// the package directory.
///
/// Use this in `setUp` / `setUpAll` whenever a test needs to open a file whose
/// path is relative to the package root (fixtures, support files, etc.).
Future<String> packageRootPath() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:compendium_core/'),
  );
  // resolvePackageUri returns the lib/ directory URI; go up one level to reach
  // the package root (packages/compendium_core/).
  return p.dirname(libUri!.toFilePath());
}
