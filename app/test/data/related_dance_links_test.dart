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

DanceLink _related(String id, String target, {String? label}) => DanceLink(
  id: id,
  kind: LinkKind.relatedDance,
  targetDanceId: target,
  label: label,
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
}
