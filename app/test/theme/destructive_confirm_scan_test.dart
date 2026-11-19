import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Confirmations whose action removes, resets, overwrites or discards the
/// user's data, by the key on their confirm button. Each must be a
/// [FilledButton] styled with `destructiveFilledButtonStyle`, and its label
/// must name the action rather than say "Continue" or "OK".
///
/// The delete confirmations proper go through `confirm_delete.dart`, whose
/// buttons are tested where it is; this list is the other destructive
/// confirmations, which build their own dialogs.
const _destructiveConfirms = <(String, String)>[
  (
    'lib/src/screens/settings/sync_devices_screen.dart',
    'sync-device-remove-confirm',
  ),
  (
    'lib/src/screens/settings/device_sync_section.dart',
    'sync-disconnect-confirm',
  ),
  (
    'lib/src/screens/settings/calling_card_layout_editor_screen.dart',
    'calling-card-reset-confirm',
  ),
  (
    'lib/src/screens/dialect_editor_screen.dart',
    'dialect-discouraged-reset-confirm',
  ),
  (
    'lib/src/screens/dialect_editor_screen.dart',
    'dialect-wordings-reset-confirm',
  ),
  (
    'lib/src/screens/import_review_screen.dart',
    'import-edit-overwrite-continue',
  ),
  ('lib/src/screens/sync_review_screen.dart', 'sync-review-merge-confirm'),
  (
    'lib/src/screens/settings/library_manager_list.dart',
    'library-merge-confirm-merge',
  ),
  (
    'lib/src/screens/settings/matrix_column_editor.dart',
    'matrix-column-reset-true-confirm',
  ),
  ('lib/src/utils/confirm_delete.dart', 'confirm-delete-confirm'),
];

void main() {
  for (final (path, key) in _destructiveConfirms) {
    test('$key is a destructive filled button that names its action', () {
      final src = File(path).readAsStringSync();
      final keyAt = src.indexOf("ValueKey('$key')");
      expect(keyAt, isNonNegative, reason: '$key not found in $path');

      // The FilledButton call whose own arguments hold the key.
      Map<String, String>? args;
      var from = keyAt;
      while (args == null) {
        final open = src.lastIndexOf(RegExp(r'FilledButton\('), from);
        expect(open, isNonNegative, reason: 'no FilledButton around $key');
        final paren = src.indexOf('(', open);
        final candidate = _topLevelArgs(src, paren);
        if ((candidate['key'] ?? '').contains("'$key'")) args = candidate;
        from = open - 1;
      }

      expect(args['style'], contains('destructiveFilledButtonStyle('));
      final label = args['child'] ?? '';
      expect(label, isNot(contains('commonContinue')));
      expect(label, isNot(contains('commonOk')));
      expect(label, isNot(contains('okButtonLabel')));
    });
  }
}

/// The named arguments of the call whose `(` is at [open], at the call's own
/// nesting depth only, mapped to their source text. Walks delimiters (and
/// skips string literals and line comments), so a multi-line or nested
/// argument is read whole.
Map<String, String> _topLevelArgs(String src, int open) {
  final args = <String, String>{};
  var depth = 0;
  var argStart = open + 1;
  String? quote;
  void finish(int end) {
    final arg = src.substring(argStart, end).trim();
    final named = RegExp(r'^(\w+)\s*:\s*([\s\S]*)$').firstMatch(arg);
    if (named != null) args[named.group(1)!] = named.group(2)!.trim();
  }

  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      i = src.indexOf('\n', i);
    } else if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
      if (depth == 0) {
        finish(i);
        return args;
      }
    } else if (c == ',' && depth == 1) {
      finish(i);
      argStart = i + 1;
    }
  }
  return args;
}
