/// Share files omit the caller's pay, Perform dialect and dance ratings, while
/// Backup keeps them (maintainer decision R2-out2-export, 2026-10-30).
///
/// The fields stay `shareable` in the registry, so the strip is in the share
/// bundle builders; these tests pin both halves of the split.
library;

import 'dart:convert';

import 'package:compendium_app/src/export/dance_share_bundle.dart';
import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance() => Dance(
  id: 'd1',
  title: "Rory O'More",
  rating: 4,
  sourceCitations: const [],
  customFields: const [],
  createdAt: _now,
  updatedAt: _now,
);

Program _program() => Program(
  id: 'p1',
  title: 'Friday Contra',
  dialectName: 'Gender-free',
  payMinorUnits: 25000,
  payCurrency: 'USD',
  slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  test('program share bundle drops pay, dialect and dance rating', () {
    final json = buildProgramShareBundle(
      _program(),
      danceFor: (_) => _dance(),
      choreographerFor: (_) => null,
      venueFor: (_) => null,
      tagFor: (_) => null,
      publishedSourceFor: (_) => null,
      customFieldFor: (_) => null,
      now: _now,
    );
    final archive = decodeArchive(json).archive;
    final program = archive.programs.single;
    expect(program.payMinorUnits, isNull);
    expect(program.payCurrency, isNull);
    expect(program.dialectName, isNull);
    expect(archive.dances.single.rating, isNull);
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final rawProgram = (raw['programs'] as List).single as Map<String, dynamic>;
    expect(rawProgram.containsKey('payMinorUnits'), isFalse);
    expect(json, isNot(contains('25000')));
    expect(json, isNot(contains('Gender-free')));
  });

  test('dance share bundle drops the rating', () {
    final archive = decodeArchive(
      buildDanceShareBundle(
        _dance(),
        choreographerFor: (_) => null,
        tagFor: (_) => null,
        publishedSourceFor: (_) => null,
        customFieldFor: (_) => null,
        now: _now,
      ),
    ).archive;
    expect(archive.dances.single.rating, isNull);
  });

  test('the strip leaves everything else on the program and dance', () {
    final json = buildProgramShareBundle(
      _program(),
      danceFor: (_) => _dance(),
      choreographerFor: (_) => null,
      venueFor: (_) => null,
      tagFor: (_) => null,
      publishedSourceFor: (_) => null,
      customFieldFor: (_) => null,
      now: _now,
    );
    final archive = decodeArchive(json).archive;
    expect(archive.programs.single.title, 'Friday Contra');
    expect(archive.programs.single.slots.single.danceId, 'd1');
    expect(archive.dances.single.title, "Rory O'More");
  });

  test('backup mode of the same codec keeps pay, dialect and rating', () {
    final json = encodeArchive(
      CompendiumArchive(
        exportedAt: _now,
        programs: [_program()],
        dances: [_dance()],
      ),
      mode: ArchiveSerializationMode.backup,
    );
    final archive = decodeArchive(json).archive;
    expect(archive.programs.single.payMinorUnits, 25000);
    expect(archive.programs.single.payCurrency, 'USD');
    expect(archive.programs.single.dialectName, 'Gender-free');
    expect(archive.dances.single.rating, 4);
  });

  test(
    'the archive codec in share mode still carries them (import re-encodes)',
    () {
      // Pins why the strip is not in the codec: import-side re-encodes use share
      // mode and must not lose a rating the user is importing.
      final json = encodeArchive(
        CompendiumArchive(exportedAt: _now, dances: [_dance()]),
        mode: ArchiveSerializationMode.share,
      );
      expect(decodeArchive(json).archive.dances.single.rating, 4);
    },
  );
}
