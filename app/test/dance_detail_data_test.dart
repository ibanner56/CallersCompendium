import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'Test Dance',
  List<String> authorIds = const [],
  List<String> tagIds = const [],
  List<DanceLink> links = const [],
  List<SourceCitation> sourceCitations = const [],
  List<CustomFieldValue> customFields = const [],
  String hook = '',
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: tagIds,
  links: links,
  sourceCitations: sourceCitations,
  customFields: customFields,
  hook: hook,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  test('load returns null when the dance does not exist', () async {
    final repos = openTestRepositories();
    final data = await DanceDetailData.load(
      repos,
      'missing',
      performedOnly: false,
    );
    expect(data, isNull);
  });

  test(
    'load hydrates author names, tag names, and formatted custom fields',
    () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Gene Hubert'),
      );
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f-text',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      );
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f-bool',
          key: 'featured',
          label: 'Featured',
          type: CustomFieldType.boolean,
        ),
      );
      await repos.dances.create(
        _dance(
          id: 'd1',
          title: 'Midwest Folklore',
          authorIds: ['c1'],
          tagIds: ['t1'],
          customFields: [
            CustomFieldValue(fieldId: 'f-text', value: 'a lovely tune'),
            CustomFieldValue(fieldId: 'f-bool', value: true),
          ],
        ),
      );

      final data = await DanceDetailData.load(
        repos,
        'd1',
        performedOnly: false,
      );

      expect(data, isNotNull);
      expect(data!.dance.title, 'Midwest Folklore');
      expect(data.authorNames, ['Gene Hubert']);
      expect(data.tagNames, ['smooth']);
      // Booleans render as Yes/No; other values via toString().
      expect(
        data.customFields,
        contains((label: 'Notes', value: 'a lovely tune')),
      );
      expect(data.customFields, contains((label: 'Featured', value: 'Yes')));
    },
  );

  test('load resolves related-dance titles and cited sources', () async {
    final repos = openTestRepositories();
    await repos.publishedSources.upsert(
      PublishedSource(
        id: 's1',
        title: 'Zesty Contras',
        author: 'Larry Jennings',
      ),
    );
    await repos.dances.create(_dance(id: 'target', title: 'Target Dance'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Cited Dance',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'target',
          ),
        ],
        sourceCitations: [SourceCitation(sourceId: 's1', page: '12-14')],
      ),
    );

    final data = await DanceDetailData.load(repos, 'd1', performedOnly: false);

    expect(data!.relatedDanceTitles['target'], 'Target Dance');
    expect(data.sourcesById['s1']?.title, 'Zesty Contras');
  });

  test(
    'load builds a cross-reference linker over other dances\' titles',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Petronella'));
      await repos.dances.create(_dance(id: 'other', title: 'Rory O\'More'));

      final data = await DanceDetailData.load(
        repos,
        'd1',
        performedOnly: false,
      );

      expect(data!.crossRefLinker.hasTitles, isTrue);
      // The linker matches another dance's title but never self-links.
      final spans = data.crossRefLinker.spansFor(
        'See Rory O\'More but not Petronella',
        baseStyle: null,
        buildLink: (matchedText, danceId) =>
            TextSpan(text: '[$danceId:$matchedText]'),
      );
      final rendered = spans
          .map((s) => s is TextSpan ? s.text ?? '' : '')
          .join();
      expect(rendered, contains('[other:Rory O\'More]'));
      // "Petronella" is this dance's own title and must not become a link.
      expect(rendered, contains('Petronella'));
      expect(rendered, isNot(contains('[d1:')));
    },
  );

  test('load includes calling history and respects performedOnly', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Petronella'));
    // One performed slot and one unperformed slot for the same dance.
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [
          ProgramSlot(
            id: 's-performed',
            position: 0,
            danceId: 'd1',
            performedAt: DateTime.utc(2026, 10, 3, 20),
          ),
        ],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await repos.programs.create(
      Program(
        id: 'p2',
        title: 'Spring Fling',
        slots: [ProgramSlot(id: 's-planned', position: 0, danceId: 'd1')],
        createdAt: _now,
        updatedAt: _now,
      ),
    );

    final all = await DanceDetailData.load(repos, 'd1', performedOnly: false);
    expect(
      all!.callingHistory.map((r) => r.slotId),
      containsAll(['s-performed', 's-planned']),
    );

    final performedOnly = await DanceDetailData.load(
      repos,
      'd1',
      performedOnly: true,
    );
    expect(performedOnly!.callingHistory.map((r) => r.slotId), ['s-performed']);
  });

  test(
    'load resolves venue labels per program (linked name, else free text)',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Petronella'));
      final grange = Venue(
        id: 'grange-hall',
        name: 'Grange Hall',
        city: 'Nelson',
      );
      await repos.venues.upsert(grange);

      // Program linked to a reusable Venue by venueId: resolves to displayName.
      await repos.programs.create(
        Program(
          id: 'p-linked',
          title: 'Autumn Ball',
          venueId: 'grange-hall',
          slots: [ProgramSlot(id: 's-linked', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      // Program with only free-text venue: falls back to the free text.
      await repos.programs.create(
        Program(
          id: 'p-freetext',
          title: 'Spring Fling',
          venue: 'Town Hall',
          slots: [ProgramSlot(id: 's-freetext', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      final data = await DanceDetailData.load(
        repos,
        'd1',
        performedOnly: false,
      );

      expect(data!.venueLabelsByProgramId['p-linked'], grange.displayName);
      expect(data.venueLabelsByProgramId['p-freetext'], 'Town Hall');
    },
  );
}
