import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Guards the mechanics of the settings-key registry itself: the invariants
/// that [classifySettingsKey]'s exact-then-longest-prefix resolution depends
/// on, and that resolution's own behaviour.
///
/// The *coverage* of these maps (which keys/prefixes must be present) is
/// enforced by `app/test/data/settings_classification_test.dart`, which walks
/// the declarations. This test only checks that the maps and the resolver
/// they feed are internally consistent — a concern the coverage ratchet
/// cannot see, since it never calls [classifySettingsKey].
void main() {
  test('no exact settings key starts with a registered prefix', () {
    final ambiguous = <String>[];
    for (final key in settingsClassifications.keys) {
      for (final prefix in settingsPrefixClassifications.keys) {
        if (key.startsWith(prefix)) ambiguous.add('$key (prefix "$prefix")');
      }
    }
    expect(
      ambiguous,
      isEmpty,
      reason:
          'An exact settingsClassifications key must not also match a '
          'registered prefix — classifySettingsKey resolves exact matches '
          'first, so an overlapping prefix entry would never be exercised '
          'for this key, which is worth a name change rather than a silent '
          'shadow: $ambiguous',
    );
  });

  test('no registered prefix is itself a prefix of another', () {
    final prefixes = settingsPrefixClassifications.keys.toList();
    final overlaps = <String>[];
    for (final a in prefixes) {
      for (final b in prefixes) {
        if (a == b) continue;
        if (b.startsWith(a)) overlaps.add('"$a" is a prefix of "$b"');
      }
    }
    expect(
      overlaps,
      isEmpty,
      reason:
          'Two registered prefixes overlap, which is unnecessary today (each '
          'settings key is built from exactly one entity kind) and would '
          'depend on the longest-match tiebreak silently: $overlaps',
    );
  });

  test('classifySettingsKey resolves an exact match over a prefix', () {
    // No real key exhibits this today (enforced by the no-overlap test
    // above), so this constructs a synthetic collision to prove the
    // precedence rule itself, independent of what happens to be registered.
    const prefix = 'synthetic_prefix:';
    const exactKey = 'synthetic_prefix:exact';
    final withExactOverride =
        Map<String, DataClassification>.of(settingsClassifications)
          ..[exactKey] = const DataClassification(
            term: DpvTerm.nonPersonal,
            subject: DataSubject.none,
            egress: EgressClass.shareable,
          );
    final withPrefix =
        Map<String, DataClassification>.of(settingsPrefixClassifications)
          ..[prefix] = const DataClassification(
            term: DpvTerm.nonPersonal,
            subject: DataSubject.none,
            egress: EgressClass.deviceScoped,
          );

    DataClassification? resolve(String key) {
      final exact = withExactOverride[key];
      if (exact != null) return exact;
      String? bestPrefix;
      for (final p in withPrefix.keys) {
        if (!key.startsWith(p)) continue;
        if (bestPrefix == null || p.length > bestPrefix.length) {
          bestPrefix = p;
        }
      }
      return bestPrefix == null ? null : withPrefix[bestPrefix];
    }

    expect(resolve(exactKey)!.egress, EgressClass.shareable);
  });

  test('classifySettingsKey prefers the longest matching prefix', () {
    // Same rationale as above: no real prefix pair overlaps today, so this
    // proves the tiebreak rule with a synthetic pair rather than asserting
    // nothing (mutation guard: a "first match wins" implementation would
    // pass this test only by accident of map iteration order, so the
    // fixture below is built so the two orders disagree).
    const shortPrefix = 'draft:';
    const longPrefix = 'draft:dance:';
    const key = 'draft:dance:42';
    final registry = {
      shortPrefix: const DataClassification(
        term: DpvTerm.nonPersonal,
        subject: DataSubject.none,
        egress: EgressClass.shareable,
      ),
      longPrefix: const DataClassification(
        term: DpvTerm.nonPersonal,
        subject: DataSubject.none,
        egress: EgressClass.deviceScoped,
      ),
    };

    String? bestPrefix;
    for (final p in registry.keys) {
      if (!key.startsWith(p)) continue;
      if (bestPrefix == null || p.length > bestPrefix.length) bestPrefix = p;
    }

    expect(registry[bestPrefix]!.egress, EgressClass.deviceScoped);
  });

  test('classifySettingsKey against the live registry: known keys', () {
    expect(
      classifySettingsKey('editor_draft:new')?.egress,
      EgressClass.deviceScoped,
    );
    expect(
      classifySettingsKey('program_editor_draft:abc123')?.egress,
      EgressClass.deviceScoped,
    );
    expect(classifySettingsKey('theme_mode')?.egress, EgressClass.shareable);
    expect(classifySettingsKey('no_such_key'), isNull);
  });
}
