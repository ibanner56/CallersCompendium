import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/sync/generated_sync_allow_list.dart';
import 'package:test/test.dart';

/// The ratchet behind [syncUserVisibleFields]: a version that differs from
/// another only in fields a comparison does not show is settled without
/// asking (sync-spec §6.3), so a synced field left out of the comparison by
/// omission would be settled silently. Every synced field must be shown or
/// declared hidden, with a reason.
void main() {
  for (final kind in SyncRecordKind.values) {
    final visible = syncUserVisibleFields(kind);
    final hidden = syncUserHiddenFields(kind);
    final synced = generatedShareableWirePaths[kind] ?? const <String>{};

    group(kind.name, () {
      test('every synced field is shown or declared hidden', () {
        if (visible == null) {
          expect(
            hidden,
            isEmpty,
            reason: 'a kind whose every field is shown hides nothing',
          );
          return;
        }
        final unclassified = <String>[];
        for (final path in synced) {
          final top = path.split('.').first;
          if (syncIdentityAndTimestampFields.contains(top)) continue;
          if (visible.contains(path) || hidden.containsKey(path)) continue;
          if (path == top) {
            unclassified.add(path);
            continue;
          }
          // A part of a field: covered by its field, unless that field is
          // hidden as a whole or shown only in part — then each part must be
          // classified on its own.
          if (hidden.containsKey(top)) continue;
          final partial = visible.any((p) => p.startsWith('$top.'));
          if (partial) unclassified.add(path);
        }
        expect(
          unclassified,
          isEmpty,
          reason:
              'Add each to syncUserVisibleFields (and to the conflict '
              "comparison's labels in app/lib/src/screens/"
              'sync_conflict_details.dart) if anything in the app shows it, or '
              'to syncUserHiddenFields with the reason if nothing does.',
        );
      });

      test('nothing is both shown and hidden, and every entry names a '
          'synced field', () {
        for (final path in [...?visible, ...hidden.keys]) {
          expect(synced, contains(path), reason: '$path is not synced');
        }
        expect(visible?.intersection(hidden.keys.toSet()) ?? {}, isEmpty);
        for (final entry in hidden.entries) {
          expect(
            entry.value.trim(),
            isNotEmpty,
            reason: '${entry.key} needs its reason',
          );
        }
      });
    });
  }

  test('a field shown only in part compares only its shown parts', () {
    Map<String, Object?> dance(String importedAt, String source) => {
      'title': 'Hey Day',
      'provenance': {'source': source, 'importedAt': importedAt},
    };
    String hash(Map<String, Object?> body) =>
        syncUserVisibleContentHash(SyncRecordKind.dance, body);

    expect(
      hash(dance('2026-01-01', 'contradb')),
      hash(dance('2026-02-01', 'contradb')),
    );
    expect(
      hash(dance('2026-01-01', 'contradb')),
      isNot(hash(dance('2026-01-01', 'callersbox'))),
    );
  });
}
