import 'dart:convert';

import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// The glossary's total byte budget ([maxUserGlossaryBytes]) against the
/// backup file it has to fit in ([kMaxBackupFileBytes]).
///
/// The budget exists because a glossary that outgrew the file cap left the user
/// unable to back up at all. These tests use the real constants and the real
/// export, so a change to the container, to the cap or to the budget that
/// breaks the arithmetic in the budget's doc comment fails here.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime.utc(2026, 10, 14, 9);

  int utf8Bytes(String s) => utf8.encode(s).length;

  /// An entry whose every text field is [ch] repeated to its bound, so it is
  /// as large as an entry can be without a payload.
  UserGlossaryEntry full(String id, String ch, {Object? payload}) {
    String fill(int n) => List.filled(n, ch).join();
    return UserGlossaryEntry(
      id: id,
      kindName: 'compound',
      name: fill(maxUserGlossaryNameLength),
      definition: fill(maxUserGlossaryTextLength),
      description: fill(maxUserGlossaryTextLength),
      keywords: [
        for (var i = 0; i < maxUserGlossaryKeywords; i++)
          fill(maxUserGlossaryNameLength),
      ],
      notes: fill(maxUserGlossaryTextLength),
      payload: payload,
      createdAt: created,
    );
  }

  /// Entries from [make] into [glossary] until one is refused; returns how many
  /// were stored. Bounded, so a glossary with no budget fails the test instead
  /// of filling the disk: the budget holds about 60 of these.
  Future<int> fillUntilRefused(
    UserGlossaryRepository glossary,
    UserGlossaryEntry Function(int) make,
  ) async {
    for (var i = 0; i < 200; i++) {
      try {
        await glossary.upsert(make(i));
      } on UserGlossaryEntryInvalid catch (e) {
        expect(e.isOverBudget, isTrue, reason: 'refused for the budget');
        return i;
      }
    }
    fail('200 maximum-size entries were stored: there is no budget');
  }

  test(
    'the budget, at its worst-case 4x, takes under a third of the file cap',
    () {
      expect(
        maxUserGlossaryBytes * 4,
        lessThanOrEqualTo(kMaxBackupFileBytes ~/ 3),
      );
    },
  );

  test('a glossary filled to the budget with the costliest text exports '
      'within 4x its counted size and well under the file cap', () async {
    final repos = openTestRepositories();
    // `"` is the costliest character: 1 byte stored, 4 in the file (escaped
    // once by the document and again by the double-encoded container).
    final stored = await fillUntilRefused(
      repos.userGlossary,
      (i) => full('e$i', '"'),
    );
    expect(stored, greaterThan(40), reason: 'room for a real glossary');

    final counted = (await repos.userGlossary.listAll()).fold<int>(
      0,
      (sum, e) =>
          sum +
          glossaryRowBytes([
            e.name,
            e.definition,
            e.description,
            jsonEncode(e.keywords),
            e.notes,
          ]),
    );
    expect(counted, lessThanOrEqualTo(maxUserGlossaryBytes));

    // The real export, with the real size guard, does not refuse it.
    final json = await BackupService(repos).exportToJson();
    final bytes = utf8Bytes(json);
    expect(bytes, lessThanOrEqualTo(counted * 4));
    expect(bytes, lessThan(kMaxBackupFileBytes ~/ 3));
    // And the multiplier is not slack: this text is nearly all quotes, and the
    // file is more than 3x what was counted (keywords are stored as JSON
    // already, so they cost 2x, not 4x), so the 4x in the budget's reasoning
    // is measured, not assumed.
    expect(bytes, greaterThan(counted * 3));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a payload costs at most twice its stored size in the file', () async {
    final repos = openTestRepositories();
    final empty = utf8Bytes(await BackupService(repos).exportToJson());
    final payload = {'pad': List.filled(100000, '"').join()};
    await repos.userGlossary.upsert(
      UserGlossaryEntry(
        id: 'p',
        kindName: 'compound',
        name: 'n',
        definition: 'd',
        description: 'd',
        payload: payload,
        createdAt: created,
      ),
    );
    final stored = jsonEncode(payload);
    final grown = utf8Bytes(await BackupService(repos).exportToJson()) - empty;
    // The payload's own bytes, plus a few hundred of envelope around the row.
    expect(grown, lessThanOrEqualTo(2 * utf8Bytes(stored) + 1024));
  });

  test('a glossary written before the budget still exports, and restores as '
      'much as fits, reporting what it had no room for', () async {
    // The roomy repository stands in for an older build with no budget.
    final source = openTestRepositories();
    final old = UserGlossaryRepository(source.db, maxBytes: 1 << 30);
    String text(int i) => '${'x' * (maxUserGlossaryTextLength - 8)}$i';
    UserGlossaryEntry entry(int i) => UserGlossaryEntry(
      id: 'e$i',
      kindName: 'compound',
      name: 'entry $i',
      definition: text(i),
      description: text(i),
      notes: text(i),
      createdAt: created.add(Duration(minutes: i)),
    );
    const total = 80;
    for (var i = 0; i < total; i++) {
      await old.upsert(entry(i));
    }
    expect(
      (await source.userGlossary.listAll()).length,
      total,
      reason: 'over the budget, but all stored',
    );

    // Over the budget, under the file cap: export works as it always did.
    final json = await BackupService(source).exportToJson();

    final target = openTestRepositories();
    final outcome = await BackupService(target).restoreFromJson(json);
    final restored = await target.userGlossary.listAll();

    expect(outcome.applied, isTrue);
    expect(restored.length, lessThan(total));
    expect(restored.length, greaterThan(total ~/ 2));
    // The ones that fit are the first ones, in file order, whole.
    expect(restored.map((e) => e.id).toList(), [
      for (var i = 0; i < restored.length; i++) 'e$i',
    ]);
    expect(restored.first.definition, text(0));
    // Each of the rest is reported as skipped, and nothing else is.
    expect(outcome.errors.length, total - restored.length);
    for (final error in outcome.errors) {
      expect(error.entityType, 'glossaryEntry');
      expect(error.message, contains('glossary is full'));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
