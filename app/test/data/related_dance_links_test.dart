import 'package:compendium_app/src/data/related_dance_links.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  List<DanceLink> links = const [],
  String title = 'Dance',
  DateTime? deletedAt,
}) => Dance(
  id: id,
  title: title,
  links: links,
  createdAt: _now,
  updatedAt: _now,
  deletedAt: deletedAt,
);

DanceLink _related(
  String id,
  String target, {
  String? label,
  bool transitive = false,
}) => DanceLink(
  id: id,
  kind: LinkKind.relatedDance,
  targetDanceId: target,
  label: label,
  transitive: transitive,
);

void main() {
  test('adds a reciprocal link when saving a new relation', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target'));
    final source = _dance(
      id: 'source',
      links: [_related('source-link', 'target')],
    );

    await saveDanceWithRelatedLinks(repos, dance: source);

    final target = await repos.dances.getById('target');
    expect(target!.links.single.targetDanceId, 'source');
  });

  test(
    'preserves an existing reciprocal note and does not duplicate it',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'source'));
      await repos.dances.create(
        _dance(
          id: 'target',
          links: [_related('target-link', 'source', label: 'keep this')],
        ),
      );
      final source = (await repos.dances.getById(
        'source',
      ))!.copyWith(links: [_related('source-link', 'target')]);
      await repos.dances.update(source);

      await saveDanceWithRelatedLinks(repos, dance: source);

      final target = await repos.dances.getById('target');
      expect(target!.links, hasLength(1));
      expect(target.links.single.id, 'target-link');
      expect(target.links.single.label, 'keep this');
    },
  );

  test('retargeting removes the old reciprocal and adds the new one', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'source'));
    await repos.dances.create(
      _dance(id: 'old', links: [_related('old-link', 'source')]),
    );
    await repos.dances.create(_dance(id: 'new'));
    final original = (await repos.dances.getById(
      'source',
    ))!.copyWith(links: [_related('source-link', 'old')]);
    await repos.dances.update(original);

    final updated = original.copyWith(
      links: [_related('source-link', 'new')],
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    await saveDanceWithRelatedLinks(repos, dance: updated, original: original);

    expect((await repos.dances.getById('old'))!.links, isEmpty);
    final newTarget = await repos.dances.getById('new');
    expect(newTarget!.links.single.targetDanceId, 'source');
  });

  test('removing a relation removes every reciprocal row', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'source'));
    final original = (await repos.dances.getById(
      'source',
    ))!.copyWith(links: [_related('source-link', 'target')]);
    await repos.dances.create(_dance(id: 'target'));
    await repos.dances.create(original);
    await repos.dances.update(
      (await repos.dances.getById('target'))!.copyWith(
        links: [
          _related('target-link-1', 'source'),
          _related('target-link-2', 'source'),
          DanceLink(
            id: 'unrelated',
            kind: LinkKind.source,
            url: 'https://example.com',
          ),
        ],
      ),
    );

    await saveDanceWithRelatedLinks(
      repos,
      dance: original.copyWith(links: [], updatedAt: DateTime.utc(2026, 1, 2)),
      original: original,
    );

    final target = await repos.dances.getById('target');
    expect(target!.links, hasLength(1));
    expect(target.links.single.id, 'unrelated');
  });

  test('removes a reciprocal row from a soft-deleted target', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'source'));
    await repos.dances.create(
      _dance(id: 'target', links: [_related('target-link', 'source')]),
    );
    final original = (await repos.dances.getById(
      'source',
    ))!.copyWith(links: [_related('source-link', 'target')]);
    await repos.dances.update(original);
    await repos.dances.softDelete('target', at: DateTime.utc(2026, 1, 2));

    await saveDanceWithRelatedLinks(
      repos,
      dance: original.copyWith(links: [], updatedAt: DateTime.utc(2026, 1, 3)),
      original: original,
    );
    await repos.dances.restore('target', at: DateTime.utc(2026, 1, 4));

    expect((await repos.dances.getById('target'))!.links, isEmpty);
  });

  test('rejects self-links before changing the source', () async {
    final repos = openTestRepositories();
    final original = _dance(id: 'source', title: 'Original');
    await repos.dances.create(original);
    final invalid = original.copyWith(
      title: 'Should not save',
      links: [_related('self-link', 'source')],
    );

    await expectLater(
      saveDanceWithRelatedLinks(repos, dance: invalid, original: original),
      throwsA(isA<RelatedDanceLinkSaveException>()),
    );
    expect((await repos.dances.getById('source'))!.title, 'Original');
  });

  test(
    'removes a legacy self-link without overwriting other source edits',
    () async {
      final repos = openTestRepositories();
      final original = _dance(
        id: 'source',
        title: 'Original',
        links: [_related('self-link', 'source')],
      );
      await repos.dances.create(original);
      final updated = original.copyWith(
        title: 'Edited',
        links: [],
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      await saveDanceWithRelatedLinks(
        repos,
        dance: updated,
        original: original,
      );

      final saved = await repos.dances.getById('source');
      expect(saved!.title, 'Edited');
      expect(saved.links, isEmpty);
    },
  );

  test('rejects a missing newly selected target before any write', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'source'));
    await repos.dances.create(
      _dance(id: 'old', links: [_related('old-link', 'source')]),
    );
    final original = (await repos.dances.getById(
      'source',
    ))!.copyWith(title: 'Original', links: [_related('source-link', 'old')]);
    await repos.dances.create(original);
    final invalid = original.copyWith(
      title: 'Should not save',
      links: [_related('source-link', 'missing')],
    );

    await expectLater(
      saveDanceWithRelatedLinks(repos, dance: invalid, original: original),
      throwsA(isA<RelatedDanceLinkSaveException>()),
    );
    expect((await repos.dances.getById('source'))!.title, 'Original');
    expect(
      (await repos.dances.getById('source'))!.links.single.targetDanceId,
      'old',
    );
    expect((await repos.dances.getById('old'))!.links.single.id, 'old-link');
    expect(await repos.dances.getById('missing'), isNull);
  });

  test('expands multiple transitive links into a complete group', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'source'));
    await repos.dances.create(_dance(id: 'left'));
    await repos.dances.create(_dance(id: 'right'));
    final source = (await repos.dances.getById('source'))!.copyWith(
      links: [
        _related('source-left', 'left', transitive: true),
        _related('source-right', 'right', transitive: true),
      ],
    );

    await saveDanceWithRelatedLinks(repos, dance: source);

    for (final id in ['source', 'left', 'right']) {
      final links = (await repos.dances.getById(id))!.links;
      final expected = switch (id) {
        'source' => ['left', 'right'],
        'left' => ['source', 'right'],
        _ => ['source', 'left'],
      };
      expect(
        links
            .where((link) => link.transitive)
            .map((link) => link.targetDanceId),
        containsAll(expected),
      );
    }
  });

  test(
    'does not traverse ordinary adjacency while expanding a group',
    () async {
      final repos = openTestRepositories();
      for (final id in ['a', 'b', 'c', 'd']) {
        await repos.dances.create(_dance(id: id));
      }
      await repos.dances.update(
        _dance(id: 'a', links: [_related('a-b', 'b', transitive: true)]),
      );
      await repos.dances.update(
        _dance(
          id: 'b',
          links: [_related('b-a', 'a', transitive: true), _related('b-c', 'c')],
        ),
      );
      await repos.dances.update(
        _dance(id: 'c', links: [_related('c-b', 'b'), _related('c-d', 'd')]),
      );
      await repos.dances.update(_dance(id: 'd', links: [_related('d-c', 'c')]));
      final original = await repos.dances.getById('b');
      final updated = original!.copyWith(
        links: [
          _related('b-a', 'a', transitive: true),
          _related('b-c', 'c', transitive: true),
        ],
      );

      await saveDanceWithRelatedLinks(
        repos,
        dance: updated,
        original: original,
      );

      final d = await repos.dances.getById('d');
      expect(d!.links.single.targetDanceId, 'c');
      expect(d.links.single.transitive, isFalse);
      expect((await repos.dances.getById('a'))!.links, hasLength(2));
      expect((await repos.dances.getById('c'))!.links, hasLength(3));
    },
  );

  test(
    'promotes an imported reciprocal row in place when explicitly enabled',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'source'));
      await repos.dances.create(
        _dance(
          id: 'target',
          links: [_related('imported-reciprocal', 'source', label: 'Imported')],
        ),
      );
      final original = await repos.dances.getById('source');
      final updated = original!.copyWith(
        links: [_related('editor-link', 'target', transitive: true)],
      );

      await saveDanceWithRelatedLinks(
        repos,
        dance: updated,
        original: original,
      );

      final reciprocal = (await repos.dances.getById('target'))!.links.single;
      expect(reciprocal.id, 'imported-reciprocal');
      expect(reciprocal.label, 'Imported');
      expect(reciprocal.transitive, isTrue);
    },
  );

  test(
    'promotes the labelled canonical row and suppresses legacy duplicates',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'source'));
      await repos.dances.create(
        _dance(
          id: 'target',
          links: [
            _related('duplicate', 'source'),
            _related('canonical', 'source', label: 'Keep me'),
          ],
        ),
      );
      final original = await repos.dances.getById('source');
      final updated = original!.copyWith(
        links: [_related('source-link', 'target', transitive: true)],
      );

      await saveDanceWithRelatedLinks(
        repos,
        dance: updated,
        original: original,
      );

      final links = (await repos.dances.getById('target'))!.links;
      expect(links, hasLength(1));
      expect(links.single.id, 'canonical');
      expect(links.single.label, 'Keep me');
      expect(links.single.transitive, isTrue);
    },
  );

  test(
    'detaches a transitive group without removing ordinary neighbours',
    () async {
      final repos = openTestRepositories();
      for (final id in ['a', 'b', 'c', 'd']) {
        await repos.dances.create(_dance(id: id));
      }
      await repos.dances.update(
        _dance(id: 'a', links: [_related('a-b', 'b', transitive: true)]),
      );
      await repos.dances.update(
        _dance(
          id: 'b',
          links: [
            _related('b-a', 'a', transitive: true),
            _related('b-c', 'c', transitive: true),
          ],
        ),
      );
      await repos.dances.update(
        _dance(
          id: 'c',
          links: [
            _related('c-b', 'b', transitive: true),
            _related('c-a', 'a', transitive: true),
            _related('c-d', 'd'),
          ],
        ),
      );
      await repos.dances.update(_dance(id: 'd', links: [_related('d-c', 'c')]));
      final original = await repos.dances.getById('b');
      final updated = original!.copyWith(
        links: [_related('b-a', 'a', transitive: true)],
      );

      await saveDanceWithRelatedLinks(
        repos,
        dance: updated,
        original: original,
      );

      for (final id in ['a', 'b', 'c']) {
        expect(
          (await repos.dances.getById(
            id,
          ))!.links.where((link) => link.transitive),
          isEmpty,
        );
      }
      expect(
        (await repos.dances.getById('c'))!.links.single.targetDanceId,
        'd',
      );
      expect(
        (await repos.dances.getById('d'))!.links.single.targetDanceId,
        'c',
      );
    },
  );

  test('can detach an old group and create a new group in one save', () async {
    final repos = openTestRepositories();
    for (final id in ['a', 'b', 'c', 'd']) {
      await repos.dances.create(_dance(id: id));
    }
    await repos.dances.update(
      _dance(id: 'a', links: [_related('a-b', 'b', transitive: true)]),
    );
    await repos.dances.update(
      _dance(
        id: 'b',
        links: [
          _related('b-a', 'a', transitive: true),
          _related('b-c', 'c', transitive: true),
        ],
      ),
    );
    await repos.dances.update(
      _dance(id: 'c', links: [_related('c-b', 'b', transitive: true)]),
    );
    final original = await repos.dances.getById('b');
    final updated = original!.copyWith(
      links: [
        _related('b-a', 'a', transitive: true),
        _related('b-d', 'd', transitive: true),
      ],
    );

    await saveDanceWithRelatedLinks(repos, dance: updated, original: original);

    expect(
      (await repos.dances.getById('a'))!.links.where((link) => link.transitive),
      isEmpty,
    );
    expect(
      (await repos.dances.getById('c'))!.links.where((link) => link.transitive),
      isEmpty,
    );
    expect(
      (await repos.dances.getById('b'))!.links
          .where((link) => link.transitive)
          .map((link) => link.targetDanceId),
      contains('d'),
    );
    expect(
      (await repos.dances.getById('d'))!.links
          .where((link) => link.transitive)
          .map((link) => link.targetDanceId),
      contains('b'),
    );
  });

  test('handles transitive cycles without looping', () async {
    final repos = openTestRepositories();
    for (final id in ['a', 'b', 'c']) {
      await repos.dances.create(_dance(id: id));
    }
    await repos.dances.update(
      _dance(id: 'a', links: [_related('a-b', 'b', transitive: true)]),
    );
    await repos.dances.update(
      _dance(id: 'b', links: [_related('b-c', 'c', transitive: true)]),
    );
    await repos.dances.update(
      _dance(id: 'c', links: [_related('c-a', 'a', transitive: true)]),
    );
    final original = await repos.dances.getById('a');

    await saveDanceWithRelatedLinks(
      repos,
      dance: original!.copyWith(title: 'Updated'),
      original: original,
    );

    expect((await repos.dances.getById('a'))!.title, 'Updated');
    for (final id in ['a', 'b', 'c']) {
      expect(
        (await repos.dances.getById(id))!.links
            .where((link) => link.transitive)
            .map((link) => link.targetDanceId),
        containsAll([
          if (id != 'a') 'a',
          if (id != 'b') 'b',
          if (id != 'c') 'c',
        ]),
      );
    }
  });

  test('rejects a transitive group beyond the inspection bound', () async {
    final repos = openTestRepositories();
    for (var i = 0; i <= kMaxTransitiveDanceGroupSize; i++) {
      await repos.dances.create(_dance(id: 'd$i'));
    }
    for (var i = 0; i < kMaxTransitiveDanceGroupSize; i++) {
      await repos.dances.update(
        _dance(
          id: 'd$i',
          links: [_related('link-$i', 'd${i + 1}', transitive: true)],
        ),
      );
    }
    final original = await repos.dances.getById('d0');

    await expectLater(
      saveDanceWithRelatedLinks(
        repos,
        dance: original!.copyWith(title: 'Should not save'),
        original: original,
      ),
      throwsA(
        isA<RelatedDanceLinkSaveException>().having(
          (e) => e.reason,
          'reason',
          'group-too-large',
        ),
      ),
    );
    expect((await repos.dances.getById('d0'))!.title, 'Dance');
  });
}
