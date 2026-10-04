import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet (audit finding D3): every settings-backed live preference in
/// `lib/main.dart` is a `PreferenceNotifier`, so it owns its key, default and
/// decoder and is reset and loaded through the one descriptor list. A bare
/// `ValueNotifier` field would have to be reset and loaded by hand again.
void main() {
  /// Fields that are deliberately plain notifiers: neither is a settings key.
  /// The dialect is fed by the dialect-library controller; the rebuild progress
  /// is transient startup UI state.
  const allowlist = {'_derivedRebuildProgress', '_dialectNotifier'};

  /// Blanks `//` comments so a commented-out or documented example is not read
  /// as a declaration.
  String blankComments(String source) =>
      source.replaceAll(RegExp(r'//[^\n]*'), '');

  /// The names of the bare `ValueNotifier` fields declared in [source].
  Set<String> bareNotifierFields(String source) {
    final code = blankComments(source);
    return {
      for (final m in RegExp(
        r'(?:final|late final)\s+(?:ValueNotifier<[^;=]*?>\s+(\w+)\s*=|(\w+)\s*=\s*ValueNotifier\b)',
      ).allMatches(code))
        (m.group(1) ?? m.group(2))!,
    };
  }

  test(
    'the detector sees bare notifier fields in the shapes main.dart uses',
    () {
      const sample = '''
  final ValueNotifier<int> _a = ValueNotifier(1);
  final ValueNotifier<Set<String>> _b =
      ValueNotifier(const <String>{});
  final _c = ValueNotifier<int>(1);
  late final _d = ValueNotifier<bool>(true);
  final _e = PreferenceNotifier<int>(key: k, defaultValue: 1);
  // final ValueNotifier<int> _commented = ValueNotifier(1);
''';
      expect(bareNotifierFields(sample), {'_a', '_b', '_c', '_d'});
    },
  );

  test('main.dart declares no bare ValueNotifier preference field', () {
    final source = File('lib/main.dart').readAsStringSync();
    final bare = bareNotifierFields(source).difference(allowlist);
    expect(
      bare,
      isEmpty,
      reason:
          'A settings-backed preference must be a PreferenceNotifier listed in '
          '_preferences. Allowlist a field here only if it is not a settings '
          'key.',
    );
  });
}
