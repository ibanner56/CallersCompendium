import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/program_editor_draft_codec.dart';
import 'package:compendium_app/src/editor/program_times.dart';

void main() {
  test('program draft round-trips purge and legacy slot markers', () {
    final draft = ProgramEditorDraft(
      title: 'Purge',
      notes: '',
      status: ProgramStatus.draft,
      hideAlternates: false,
      slots: [
        ProgramSlot(
          id: 'purge',
          position: 0,
          text: 'Lady of the Lake',
          isPurgedDance: true,
        ),
        ProgramSlot(
          id: 'legacy',
          position: 1,
          text: 'Old text',
          isPurgedDance: null,
        ),
      ],
    );

    final decoded = decodeProgramDraft(encodeProgramDraft(draft));

    expect(decoded.slots[0].isPurgedDance, isTrue);
    expect(decoded.slots[1].isPurgedDance, isNull);
  });

  test('legacy plannedMinutes draft value becomes danceMinutes', () {
    final decoded = decodeProgramDraft({
      'v': 1,
      'title': 'Legacy',
      'notes': '',
      'status': 'draft',
      'hideAlternates': false,
      'slots': [
        {
          'id': 's1',
          'position': 0,
          'danceId': 'd1',
          'isAlt': false,
          'plannedMinutes': 8,
        },
      ],
    });

    expect(decoded.slots.single.walkthroughMinutes, isNull);
    expect(decoded.slots.single.danceMinutes, 8);
  });

  group('pay fields (issue #1418)', () {
    test(
      'round-trip keeps the typed text, even an invalid one, and currency',
      () {
        final draft = ProgramEditorDraft(
          title: 'Pay',
          notes: '',
          status: ProgramStatus.draft,
          hideAlternates: false,
          payText: '12.',
          payCurrency: 'GBP',
          slots: const [],
        );

        final decoded = decodeProgramDraft(encodeProgramDraft(draft));

        expect(decoded.hasPay, isTrue);
        expect(decoded.payText, '12.');
        expect(decoded.payCurrency, 'GBP');
      },
    );

    test('an explicitly empty pay round-trips as captured, not as absent', () {
      final draft = ProgramEditorDraft(
        title: 'Pay',
        notes: '',
        status: ProgramStatus.draft,
        hideAlternates: false,
        slots: const [],
      );

      final decoded = decodeProgramDraft(encodeProgramDraft(draft));

      expect(decoded.hasPay, isTrue);
      expect(decoded.payText, '');
      expect(decoded.payCurrency, isNull);
    });

    test('an old draft without pay keys decodes as never captured', () {
      final decoded = decodeProgramDraft({
        'v': 1,
        'title': 'Old',
        'notes': '',
        'status': 'draft',
        'hideAlternates': false,
        'slots': <Object?>[],
      });

      expect(decoded.hasPay, isFalse);
      expect(decoded.payText, '');
      expect(decoded.payCurrency, isNull);
    });

    test('a draft encoded without hasPay omits the keys', () {
      final encoded = encodeProgramDraft(
        ProgramEditorDraft(
          title: 'Old',
          notes: '',
          status: ProgramStatus.draft,
          hideAlternates: false,
          hasPay: false,
          slots: const [],
        ),
      );

      expect(encoded, isNot(contains('payText')));
      expect(decodeProgramDraft(encoded).hasPay, isFalse);
    });
  });

  group('times (#2350)', () {
    ProgramEditorDraft draft(ProgramTimes times) => ProgramEditorDraft(
      title: 'T',
      notes: '',
      status: ProgramStatus.draft,
      hideAlternates: false,
      times: times,
      slots: const [],
    );

    test('round-trip, including a cleared time and midnight', () {
      const times = ProgramTimes(start: 1170, end: 0, arrival: 1439);
      final decoded = decodeProgramDraft(encodeProgramDraft(draft(times)));
      expect(decoded.hasTimes, isTrue);
      expect(decoded.times, times);
      expect(decoded.times.lesson, isNull);
    });

    test('none set still records that the draft captured them', () {
      final decoded = decodeProgramDraft(
        encodeProgramDraft(draft(const ProgramTimes())),
      );
      expect(decoded.hasTimes, isTrue);
      expect(decoded.times, const ProgramTimes());
    });

    test('an old draft without the key decodes as never captured', () {
      final decoded = decodeProgramDraft({
        'v': 1,
        'title': 'Old',
        'notes': '',
        'status': 'draft',
        'hideAlternates': false,
        'slots': <Object?>[],
      });
      expect(decoded.hasTimes, isFalse);
    });

    test('a malformed time is rejected', () {
      for (final bad in <Object>[1440, -1, '19:30', <Object?>[]]) {
        expect(
          () => decodeProgramDraft({
            'v': 1,
            'title': 'T',
            'notes': '',
            'status': 'draft',
            'hideAlternates': false,
            'times': {'start': bad},
            'slots': <Object?>[],
          }),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(
        () => decodeProgramDraft({
          'v': 1,
          'title': 'T',
          'notes': '',
          'status': 'draft',
          'hideAlternates': false,
          'times': 'start',
          'slots': <Object?>[],
        }),
        throwsFormatException,
      );
    });
  });
}
