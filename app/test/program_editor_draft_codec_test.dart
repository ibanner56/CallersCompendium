import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/program_editor_draft_codec.dart';

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
}
