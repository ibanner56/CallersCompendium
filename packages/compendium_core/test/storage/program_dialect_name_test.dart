// Issue #1554: a program's dialect reference is a *name*, and it only works if
// it stays byte-equal to the dialect library's name for that dialect. These
// tests pin the two boundaries that decide that: the library reaches storage
// through SettingsRepository.set (which NFC-normalizes shareable settings), and
// a program reaches peers through Device Sync admission (which rejects a body
// that differs from its normalized form).
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveProgramToJson;
import 'package:test/test.dart';

import 'test_database.dart';

// "Café Calls", decomposed (e + combining acute) and precomposed.
const _decomposed = 'Café Calls';
const _precomposed = 'Café Calls';

Program _program({String? dialectName}) => Program(
  id: 'p1',
  title: 'Spring Dance',
  dialectName: dialectName,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

SyncMergeCandidate _candidate(Program program) => SyncMergeCandidate(
  blob: SyncRecordBlob(
    kind: SyncRecordKind.program,
    id: program.id,
    updatedAt: program.updatedAt,
    deletedAt: null,
    existenceAt: program.updatedAt,
    body: archiveProgramToJson(program, includeOptionalFields: true),
  ),
  peerId: 'peer-a',
);

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('the repository stores dialectName NFC-normalized', () async {
    await repositories.programs.create(_program(dialectName: _decomposed));
    final loaded = await repositories.programs.getById('p1');
    expect(loaded!.dialectName, _precomposed);
  });

  test('a stored reference resolves against the library after the library '
      'round-trips settings storage', () async {
    final custom = Dialect.larksRobins.copyWith(name: _decomposed);
    await repositories.settings.set('custom_dialects', [custom.toJson()]);
    await repositories.programs.create(_program(dialectName: custom.name));

    final stored =
        (await repositories.settings.get('custom_dialects'))! as List;
    final library = [
      for (final d in stored)
        Dialect.fromJson((d as Map).cast<String, Object?>()),
    ];
    // Precondition this design rests on: the library's own name really is
    // normalized on its way to storage. If this ever stops holding, the
    // repository normalization above is no longer the right call.
    expect(library.single.name, _precomposed);

    final program = await repositories.programs.getById('p1');
    expect(
      Dialect.resolveByName(program!.dialectName, candidates: library),
      isNotNull,
    );
  });

  test('a program written through the repository is admitted by Device Sync, '
      'where an un-normalized reference is rejected', () async {
    await repositories.programs.create(_program(dialectName: _decomposed));
    final stored = (await repositories.programs.getById('p1'))!;
    expect(
      admitSyncInboundCandidate(_candidate(stored)).candidate,
      isNotNull,
      reason: 'a repository-written reference must be canonical on the wire',
    );

    // The same program, built in memory without passing through the
    // repository, still carries the decomposed name and is not canonical.
    final rejected = admitSyncInboundCandidate(
      _candidate(_program(dialectName: _decomposed)),
    );
    expect(rejected.candidate, isNull);
    expect(rejected.report!.code, SyncReportCode.nonCanonicalWireBody);
  });
}
