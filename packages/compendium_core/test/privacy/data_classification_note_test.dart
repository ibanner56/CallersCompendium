import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The "say why" rule for the data-classification registries, as a test.
///
/// `CONTRIBUTING.md` says a reviewer should never have to guess why a
/// personal-data field is `shareable`. This makes the rule mechanical. A
/// non-empty, trimmed `note` is required on:
///
/// 1. every entry whose egress is not [EgressClass.shareable];
/// 2. every [EgressClass.shareable] entry whose subject is not
///    [DataSubject.none];
/// 3. every entry whose subject is [DataSubject.thirdParty], whatever its
///    egress, with **no exemption**: venue contacts and choreographers never
///    touch this app and cannot consent to a transfer, so the reason is always
///    owed.
///
/// Rules 1 and 2 already cover every third-party entry (it is either
/// non-shareable or shareable with a subject); rule 3 is stated on its own
/// because the exemption below must never reach it, and a test that says so
/// fails if that changes.
///
/// **The one exemption** is [preferenceSettingKeys]: the app-user preference
/// settings that share the `_preference` classification (`appUser`,
/// `shareable`, no note). They are exempt by identity, as
/// `syncBookkeepingTables` is derived, because the reason is the same on every
/// one (a working preference, which is the same on any device the user owns) and
/// is stated once on the constant. A key leaves the exemption by being given its
/// own classification; there is no other way in.
///
/// The check is a function over a registry map, so the same code runs on the
/// real registries (which must be clean) and on small synthetic ones that must
/// trip it and name the key.
bool _hasNote(DataClassification c) => c.note?.trim().isNotEmpty ?? false;

/// Entries that owe a note and have none. [exemptKeys] are skipped unless the
/// entry's subject is third-party: that case has no exemption.
List<String> missingNotes(
  Map<String, DataClassification> registry, {
  Set<String> exemptKeys = const {},
}) {
  final problems = <String>[];
  for (final entry in registry.entries) {
    final c = entry.value;
    final owed =
        c.egress != EgressClass.shareable || // rule 1
        c.subject != DataSubject.none || // rule 2
        c.subject == DataSubject.thirdParty; // rule 3
    if (!owed || _hasNote(c)) continue;
    if (exemptKeys.contains(entry.key) && c.subject != DataSubject.thirdParty) {
      continue;
    }
    problems.add(
      '${entry.key}: ${c.subject.name} / ${c.egress.name} entry has no note',
    );
  }
  return problems;
}

void main() {
  group('the real registries say why', () {
    test('every database column that owes a note has one', () {
      expect(missingNotes(fieldClassifications), isEmpty);
    });

    test('every settings key that owes a note has one', () {
      expect(
        missingNotes(
          settingsClassifications,
          exemptKeys: preferenceSettingKeys,
        ),
        isEmpty,
      );
    });

    test('every settings-prefix entry that owes a note has one', () {
      expect(missingNotes(settingsPrefixClassifications), isEmpty);
    });

    test('the venue postal address, once unexplained, now says why', () {
      const columns = [
        'address1',
        'address2',
        'city',
        'state_prov',
        'country',
        'postal_code',
        'plus4',
      ];
      for (final column in columns) {
        final c = fieldClassifications['venues.$column']!;
        expect(c.subject, DataSubject.thirdParty, reason: column);
        expect(c.egress, EgressClass.deviceLocal, reason: column);
        expect(_hasNote(c), isTrue, reason: 'venues.$column has no note');
      }
    });
  });

  group('the preference exemption is exactly the shared constant', () {
    test('it is not empty and every member is a settings entry', () {
      expect(preferenceSettingKeys, isNotEmpty);
      expect(
        preferenceSettingKeys.difference(settingsClassifications.keys.toSet()),
        isEmpty,
      );
    });

    test(
      'every exempt key is an app-user, shareable, note-free preference',
      () {
        for (final key in preferenceSettingKeys) {
          final c = settingsClassifications[key]!;
          expect(c.subject, DataSubject.appUser, reason: key);
          expect(c.egress, EgressClass.shareable, reason: key);
          expect(c.term, DpvTerm.nonPersonal, reason: key);
          expect(c.note, isNull, reason: key);
        }
      },
    );

    test('no third-party entry is exempt', () {
      for (final key in preferenceSettingKeys) {
        expect(
          settingsClassifications[key]!.subject,
          isNot(DataSubject.thirdParty),
          reason: key,
        );
      }
    });
  });

  group('the rule fails on what it is for', () {
    DataClassification entry(
      DataSubject subject,
      EgressClass egress, {
      String? note,
    }) => DataClassification(
      term: DpvTerm.nonPersonal,
      subject: subject,
      egress: egress,
      note: note,
    );

    test('a non-shareable entry with no note is named (rule 1)', () {
      for (final egress in EgressClass.values) {
        if (egress == EgressClass.shareable) continue;
        final problems = missingNotes({'a.b': entry(DataSubject.none, egress)});
        expect(problems, ['a.b: none / ${egress.name} entry has no note']);
      }
    });

    test('a shareable entry about a person with no note is named (rule 2)', () {
      expect(
        missingNotes({
          'a.b': entry(DataSubject.appUser, EgressClass.shareable),
        }),
        ['a.b: appUser / shareable entry has no note'],
      );
    });

    test('a third-party entry with no note is named, whatever its egress', () {
      for (final egress in EgressClass.values) {
        expect(missingNotes({'a.b': entry(DataSubject.thirdParty, egress)}), [
          'a.b: thirdParty / ${egress.name} entry has no note',
        ], reason: egress.name);
      }
    });

    test('the preference exemption never reaches a third-party entry', () {
      expect(
        missingNotes(
          {'a.b': entry(DataSubject.thirdParty, EgressClass.shareable)},
          exemptKeys: {'a.b'},
        ),
        ['a.b: thirdParty / shareable entry has no note'],
      );
    });

    test('the exemption does skip an exempt app-user preference', () {
      expect(
        missingNotes(
          {'a.b': entry(DataSubject.appUser, EgressClass.shareable)},
          exemptKeys: {'a.b'},
        ),
        isEmpty,
      );
    });

    test('an empty or whitespace-only note is no note', () {
      for (final blank in ['', ' ', '\n\t ']) {
        expect(
          missingNotes({
            'a.b': entry(
              DataSubject.none,
              EgressClass.deviceLocal,
              note: blank,
            ),
          }),
          hasLength(1),
          reason: 'note ${blank.codeUnits}',
        );
      }
    });

    test('a shareable entry about nobody needs no note', () {
      expect(
        missingNotes({'a.b': entry(DataSubject.none, EgressClass.shareable)}),
        isEmpty,
      );
    });

    test('a real note satisfies every rule', () {
      for (final subject in DataSubject.values) {
        for (final egress in EgressClass.values) {
          expect(
            missingNotes({
              'a.b': entry(subject, egress, note: 'Because of the reason.'),
            }),
            isEmpty,
            reason: '${subject.name} / ${egress.name}',
          );
        }
      }
    });
  });
}
