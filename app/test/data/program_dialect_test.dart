import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/program_dialect.dart';

import '../support/test_repositories.dart';

void main() {
  late DialectLibraryController library;

  setUp(() async {
    final repos = openTestRepositories();
    await repos.ensureMigrated();
    library = DialectLibraryController(repos.settings);
    await library.load();
    addTearDown(library.dispose);
  });

  test('null and unknown names resolve to null (fall back to the app '
      'dialect)', () {
    expect(resolveProgramDialect(null, library), isNull);
    expect(resolveProgramDialect('No Such Dialect', library), isNull);
    expect(resolveProgramDialect('', library), isNull);
  });

  test('resolves a shipped preset and a custom dialect by name', () async {
    await library.upsert(Dialect.leadsFollows.copyWith(name: 'Mine'));

    expect(
      resolveProgramDialect('Larks/Robins', library)?.name,
      'Larks/Robins',
    );
    expect(resolveProgramDialect('Mine', library)?.name, 'Mine');
  });

  test('a renamed or deleted dialect stops resolving without any write to '
      'the program', () async {
    await library.upsert(Dialect.leadsFollows.copyWith(name: 'Mine'));
    expect(resolveProgramDialect('Mine', library), isNotNull);

    await library.rename('Mine', 'Ours');
    expect(resolveProgramDialect('Mine', library), isNull);
    expect(resolveProgramDialect('Ours', library), isNotNull);

    await library.delete('Ours');
    expect(resolveProgramDialect('Ours', library), isNull);
  });

  test('matches across NFC and NFD spellings of the same name', () async {
    await library.upsert(Dialect.leadsFollows.copyWith(name: 'Café Calls'));

    final viaNfc = resolveProgramDialect('Café Calls', library);
    expect(viaNfc, isNotNull);
    expect(viaNfc!.name, 'Café Calls');
    expect(resolveProgramDialect('Café Calls', library), isNotNull);
  });
}
