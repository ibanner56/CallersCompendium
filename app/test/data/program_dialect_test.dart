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

  test('with both spellings of a name in the library, each name resolves to '
      'its own dialect (exact match first)', () async {
    // The library enforces uniqueness by raw string equality, so canonically
    // equal spellings can coexist in memory until it reloads.
    final nfc = Dialect.larksRobins.copyWith(name: 'Caf\u00e9 Calls');
    final nfd = Dialect.leadsFollows.copyWith(name: 'Cafe\u0301 Calls');
    await library.upsert(nfc);
    await library.upsert(nfd);

    expect(
      resolveProgramDialect('Cafe\u0301 Calls', library)?.roles,
      nfd.roles,
      reason: 'picking the second spelling must not render the first',
    );
    expect(resolveProgramDialect('Caf\u00e9 Calls', library)?.roles, nfc.roles);
  });

  test('matches across NFC and NFD spellings of the same name', () async {
    await library.upsert(Dialect.leadsFollows.copyWith(name: 'Café Calls'));

    final viaNfc = resolveProgramDialect('Café Calls', library);
    expect(viaNfc, isNotNull);
    expect(viaNfc!.name, 'Café Calls');
    expect(resolveProgramDialect('Café Calls', library), isNotNull);
  });

  group('across dance forms', () {
    late DialectLibraries libraries;

    setUp(() async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      libraries = DialectLibraries(repos.settings);
      await libraries.load();
      addTearDown(libraries.dispose);
      await libraries.contra.upsert(
        Dialect(name: 'Shared', roles: const {'role1': RoleTerm('Jay')}),
      );
      await libraries
          .forForm(DanceForm.ecd)
          .upsert(
            Dialect(name: 'Shared', roles: const {'role1': RoleTerm('Wren')}),
          );
      await libraries
          .forForm(DanceForm.square)
          .upsert(Dialect(name: 'Square only'));
    });

    test('lists each name once, presets first', () {
      expect(programDialectNames(libraries), [
        ...Dialect.presets.map((d) => d.name),
        'Shared',
        'Square only',
      ]);
    });

    test('resolves a name from whichever form has it', () {
      expect(
        resolveProgramDialectInAnyForm('Square only', libraries)?.name,
        'Square only',
      );
      expect(
        resolveProgramDialectInAnyForm(
          'Shared',
          libraries,
        )?.roles['role1']?.singular,
        'Jay',
      );
      expect(resolveProgramDialectInAnyForm('Gone', libraries), isNull);
      expect(resolveProgramDialectInAnyForm(null, libraries), isNull);
    });

    test('each form resolves its own dialect of a shared name', () {
      expect(
        resolveProgramDialect(
          'Shared',
          libraries.forForm(DanceForm.ecd),
        )?.roles['role1']?.singular,
        'Wren',
      );
      expect(resolveProgramDialect('Square only', libraries.contra), isNull);
    });
  });
}
