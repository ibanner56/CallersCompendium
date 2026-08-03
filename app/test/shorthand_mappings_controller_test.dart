import 'dart:convert';

import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'package:compendium_core/testing.dart';

/// A taxonomy-valid neighbor swing.
Figure _swing({String who = 'neighbors', int beats = 16}) =>
    testFigure(move: 'swing', params: {'who': who, 'beats': beats});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads to empty when nothing is persisted', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isEmpty, isTrue);
    expect(controller.mappings, isEmpty);
  });

  test('upsert persists and survives a reload (round-trip)', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await controller.upsert(
      ShorthandMapping(token: 'BnS', figures: [_swing()]),
    );

    // A fresh controller over the same store decodes the saved mapping,
    // preserving the original casing for display.
    final reloaded = ShorthandMappingsController(repos.settings);
    addTearDown(reloaded.dispose);
    await reloaded.load();

    expect(reloaded.mappings, hasLength(1));
    expect(reloaded.mappings.single.token, 'BnS');
    expect(reloaded.mappings.single.normalizedToken, 'bns');
    expect(reloaded.mappings.single.figures.single.move, 'swing');
  });

  test('upsert supports an ordered multi-figure target', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    final circle = parseFreeTextFigureEntry('circle left 3/4').single;
    await controller.upsert(
      ShorthandMapping(token: 'combo', figures: [_swing(), circle]),
    );

    final store = controller.store.resolve('combo');
    expect(store, hasLength(2));
    expect(store![0].move, 'swing');
    expect(store[1].move, 'circle');
  });

  test('upsert rejects a case-insensitive duplicate token', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await controller.upsert(ShorthandMapping(token: 'sw', figures: [_swing()]));

    expect(
      () =>
          controller.upsert(ShorthandMapping(token: 'SW', figures: [_swing()])),
      throwsArgumentError,
    );
    expect(controller.mappings, hasLength(1));
  });

  test('upsert rejects an empty or over-long token', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    expect(
      () => controller.upsert(
        ShorthandMapping(token: '   ', figures: [_swing()]),
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.upsert(
        ShorthandMapping(
          token: 'x' * (maxShorthandTokenLength + 1),
          figures: [_swing()],
        ),
      ),
      throwsArgumentError,
    );
    expect(controller.mappings, isEmpty);
  });

  test('upsert rejects an empty or oversized figures list', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    // Empty expansion (would make resolve() return `[]`, a no-op HIT).
    expect(
      () => controller.upsert(
        ShorthandMapping(token: 'empty', figures: const []),
      ),
      throwsArgumentError,
    );
    // Over the bounded target-figure count.
    expect(
      () => controller.upsert(
        ShorthandMapping(
          token: 'huge',
          figures: [
            for (var i = 0; i < maxShorthandTargetFigures + 1; i++) _swing(),
          ],
        ),
      ),
      throwsArgumentError,
    );
    expect(controller.mappings, isEmpty);
  });

  test('upsert with an index replaces (and can re-case) in place', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await controller.upsert(
      ShorthandMapping(token: 'ns', figures: [_swing(beats: 8)]),
    );
    await controller.upsert(
      ShorthandMapping(token: 'NS', figures: [_swing(beats: 16)]),
      index: 0,
    );

    expect(controller.mappings, hasLength(1));
    expect(controller.mappings.single.token, 'NS');
    expect(controller.mappings.single.figures.single.params['beats'], 16);
  });

  test('removeAt deletes the mapping and persists the removal', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await controller.upsert(ShorthandMapping(token: 'ns', figures: [_swing()]));
    await controller.removeAt(0);

    expect(controller.mappings, isEmpty);
    expect(await repos.settings.get(kShorthandMappingsKey), isEmpty);
  });

  test('a corrupt persisted payload decodes to empty (never throws)', () async {
    final repos = openTestRepositories();
    // Hostile / malformed store: unknown move, oversized junk, wrong shape.
    await repos.settings.set(kShorthandMappingsKey, [
      {'token': 'bad', 'figures': 'not-a-list'},
      {
        'token': 'unknown',
        'figures': <Object?>[
          {'move': 'definitely_not_a_real_move', 'params': <String, Object?>{}},
        ],
      },
      'a bare string that is not a mapping object',
      42,
    ]);

    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await controller.load();

    expect(controller.mappings, isEmpty);
  });

  test(
    'hasToken matches case-insensitively with an optional exception',
    () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);

      await controller.upsert(
        ShorthandMapping(token: 'Ns', figures: [_swing()]),
      );

      expect(controller.hasToken('ns'), isTrue);
      expect(controller.hasToken('NS'), isTrue);
      expect(controller.hasToken('ns', exceptIndex: 0), isFalse);
      expect(controller.hasToken('other'), isFalse);
    },
  );

  test('encode round-trips through JSON and decodes back', () async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await controller.upsert(
      ShorthandMapping(token: 'bns', figures: [_swing()]),
    );

    final json = jsonEncode(controller.store.toJson());
    final decoded = ShorthandMappings.decode(json, taxonomy: contraTaxonomy);
    expect(decoded.resolve('bns'), hasLength(1));
  });
}
