import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/data/archive_intake_service.dart';
import 'package:compendium_app/src/data/dance_link_intake.dart';
import 'package:compendium_app/src/export/dance_code.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dance_links.dart';

Future<DanceLinkFailure?> _refusalOf(String link) async {
  try {
    await validateDanceLink(link);
  } on DanceLinkException catch (e) {
    return e.failure;
  }
  return null;
}

void main() {
  group('looksLikeDanceLink', () {
    test('a ccdance link, in any case, with surrounding whitespace', () {
      expect(looksLikeDanceLink(goodDanceLink()), isTrue);
      expect(looksLikeDanceLink('  CCDance://1/abc\n'), isTrue);
      expect(looksLikeDanceLink('ccdance:'), isTrue);
    });

    test('not a web link, a title, or another scheme', () {
      expect(looksLikeDanceLink('https://contradb.com/dances/1'), isFalse);
      expect(looksLikeDanceLink('Chorus Jig'), isFalse);
      expect(looksLikeDanceLink('callerscompendium://wake'), isFalse);
      expect(looksLikeDanceLink('ccdanc'), isFalse);
      expect(looksLikeDanceLink(''), isFalse);
    });
  });

  group('validateDanceLink', () {
    test('a good link validates as the archive it carries', () async {
      final validation = await validateDanceLink(goodDanceLink());
      expect(validation.isRejected, isFalse);
      expect(validation.json, danceLinkBundleJson());
      expect(validation.archive!.dances.single.title, danceLinkTitle);
    });

    test('surrounding whitespace is ignored', () async {
      final validation = await validateDanceLink(' ${goodDanceLink()}\n');
      expect(validation.isRejected, isFalse);
    });

    test(
      'an archive from a newer schema is not refused, as for a file',
      () async {
        final validation = await validateDanceLink(newerSchemaDanceLink());
        expect(validation.isRejected, isFalse);
        expect(validation.archive!.dances.single.title, danceLinkTitle);
      },
    );

    test('an archive with nothing in it is refused by intake', () async {
      final validation = await validateDanceLink(emptyArchiveDanceLink());
      expect(validation.reason, ArchiveIntakeRejectionReason.noContent);
    });

    test('a link over the length cap is refused before it is read', () async {
      expect(await _refusalOf(overLengthDanceLink()), DanceLinkFailure.tooLong);
    });

    test('a link with an unknown version is refused', () async {
      expect(
        await _refusalOf(unknownVersionDanceLink()),
        DanceLinkFailure.unknownVersion,
      );
    });

    test(
      'a truncated payload is refused, never read as a shorter dance',
      () async {
        expect(await _refusalOf(truncatedDanceLink()), isNotNull);
      },
    );

    test('a payload that inflates past the cap is refused', () async {
      expect(
        await _refusalOf(inflateBombDanceLink()),
        DanceLinkFailure.tooLarge,
      );
    });
  });

  group('danceLinkRefusalMessage', () {
    final l10n = AppLocalizationsEn();

    test('an unknown version asks the user to update', () {
      expect(
        danceLinkRefusalMessage(l10n, DanceLinkFailure.unknownVersion),
        l10n.danceLinkRefusedNewerVersion,
      );
    });

    test('every other failure says the code is damaged', () {
      for (final failure in DanceLinkFailure.values) {
        if (failure == DanceLinkFailure.unknownVersion) continue;
        expect(
          danceLinkRefusalMessage(l10n, failure),
          l10n.danceLinkRefusedDamaged,
          reason: failure.name,
        );
      }
    });
  });
}
