/// A shared program file, the programs CSV and the set-list PDF carry no event
/// rule data (#2340): the rules applied to a program are the caller's own
/// planning aids, kept by sync and backups only (registry
/// `programs.event_rule_ids`).
library;

import 'dart:convert';

import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/pdf_probe.dart';

final _now = DateTime.utc(2026, 1, 1);

// Ids no other field holds, so any trace of them is the applied rules.
const _ruleIds = ['rule-id-qqq', 'rule-id-zzz'];

Program _program() => Program(
  id: 'p1',
  title: 'Friday Contra',
  eventRuleIds: _ruleIds,
  slots: [ProgramSlot(id: 's0', position: 0, text: 'Waltz')],
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the program share file carries no applied rules', () {
    final json = buildProgramShareBundle(
      _program(),
      blankedDanceSlotText: 'Deleted dance',
      danceFor: (_) => null,
      choreographerFor: (_) => null,
      venueFor: (_) => null,
      tagFor: (_) => null,
      publishedSourceFor: (_) => null,
      customFieldFor: (_) => null,
      now: _now,
    );
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final rawProgram = (raw['programs'] as List).single as Map<String, dynamic>;
    expect(rawProgram.containsKey('eventRuleIds'), isFalse);
    for (final id in _ruleIds) {
      expect(json, isNot(contains(id)));
    }
    expect(decodeArchive(json).archive.programs.single.eventRuleIds, isEmpty);
  });

  test('the CSV and share strips both drop them, and nothing else', () {
    expect(sanitizeProgramForShare(_program()).eventRuleIds, isEmpty);
    expect(sanitizeProgramForCsv(_program()).eventRuleIds, isEmpty);
    expect(sanitizeProgramForCsv(_program()).title, 'Friday Contra');
  });

  test('the set-list PDF prints no rule data', () async {
    final text = pdfText(
      await buildProgramPdf(
        _program(),
        titleFor: (_) => null,
        theme: pw.ThemeData.base(),
      ),
    );
    expect(text, contains('Friday Contra'));
    for (final id in _ruleIds) {
      expect(text, isNot(contains(id)));
    }
  });

  test('a backup keeps them', () {
    final json = encodeArchive(
      CompendiumArchive(exportedAt: _now, programs: [_program()]),
      mode: ArchiveSerializationMode.backup,
    );
    expect(decodeArchive(json).archive.programs.single.eventRuleIds, _ruleIds);
  });
}
