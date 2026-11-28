import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_scan.dart';

/// Confirmations whose action removes, resets, overwrites or discards the
/// user's data, by the key on their confirm button. Each must be a
/// [FilledButton] styled with `destructiveFilledButtonStyle`, and its label
/// must name the action rather than say "Continue" or "OK".
///
/// This list pins the confirmations whose label is not itself a destructive
/// verb (Merge, Disconnect, Continue past an overwrite warning) as well as some
/// that are. Every other dialog action whose label names a destructive verb is
/// found by the discovery scan in `main`, so a confirmation added later is
/// checked without being listed here.
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

/// The words a button label's l10n key uses for an action that removes,
/// resets, overwrites or discards the user's data. Matched as whole words of
/// the camelCase key (`commonDelete`, `callingCardEditorReset`), so
/// `recentlyDeletedRestore` (Restore, from the bin) is not one.
const _destructiveVerbs = {
  'delete',
  'remove',
  'reset',
  'replace',
  'discard',
  'clear',
  'wipe',
  'purge',
  'overwrite',
  'erase',
};

/// Whether one of the camelCase words of the l10n [key] is a destructive verb.
bool _namesDestructiveVerb(String key) => key
    .split(RegExp(r'(?=[A-Z0-9])'))
    .any((word) => _destructiveVerbs.contains(word.toLowerCase()));

/// Dialog action buttons whose label names a destructive verb but which do
/// not themselves confirm the destructive action, by `path#label key`, each
/// with the reason. A button that confirms one must be a destructive
/// [FilledButton]; one listed here must still exist (see the staleness
/// check), so the list cannot outlive its entries.
const _notConfirmations = <String, String>{
  'lib/src/screens/dance_editor_screen.dart#danceEditorDiscard':
      'a choice offered on opening (Restore an autosaved draft, the filled '
      'primary, or Discard it), not a confirmation of an action the user took',
  'lib/src/screens/program_editor_screen.dart#programsDraftDiscard':
      'a choice offered on opening (Restore an autosaved draft, the filled '
      'primary, or Discard it), not a confirmation of an action the user took',
  'lib/src/widgets/batch_tag_dialog.dart#collectionBatchTagRemoveConfirm':
      'a picker\'s apply button (Add or Remove the ticked tags); the batch '
      'change it applies offers Undo',
};

/// A dialog action button: its file, line, key (the source text of its `key`
/// argument, or empty), the l10n keys its label reads, and whether it follows
/// the rule.
typedef DialogAction = ({
  String path,
  int line,
  String key,
  List<String> labelKeys,
  bool destructiveFilled,
});

final _alertDialog = RegExp(r'(?<![\w.])AlertDialog(?:\.adaptive)?\s*\(');
final _button = RegExp(
  r'(?<![\w.])(FilledButton|TextButton|OutlinedButton|ElevatedButton)'
  r'(?:\.(\w+))?\s*\(',
);

/// Every button in the `actions:` of every [AlertDialog] in [source], whose
/// label reads one of [l10nKeys] (directly or through `??`, a conditional or
/// a wrapping widget: every key named in its `child` / `label` counts).
List<DialogAction> dialogActionsIn(
  String path,
  String source,
  Set<String> l10nKeys,
) {
  final code = codeOnly(source);
  final found = <DialogAction>[];
  for (final dialog in _alertDialog.allMatches(code)) {
    final actions = callArgs(
      source,
      dialog.end - 1,
      code: code,
    ).where((a) => a.name == 'actions').firstOrNull;
    if (actions == null) continue;
    final region = code.substring(actions.start, actions.end);
    for (final b in _button.allMatches(region)) {
      final open = actions.start + b.end - 1;
      final all = callArgs(source, open, code: code);
      final args = {
        for (final a in all)
          if (a.name != null) a.name!: a.text,
      };
      // The label as code, so a key named inside a string is not read.
      final label = [
        for (final a in all)
          if (a.name == 'child' || a.name == 'label')
            code.substring(a.start, a.end),
      ].join(' ');
      final keys = [
        for (final m in RegExp(r'\.(\w+)\b').allMatches(label))
          if (l10nKeys.contains(m.group(1))) m.group(1)!,
      ];
      final variant = b.group(2);
      found.add((
        path: path,
        line: lineAt(source, actions.start + b.start),
        key: args['key'] ?? '',
        labelKeys: keys,
        destructiveFilled:
            b.group(1) == 'FilledButton' &&
            (variant == null || variant == 'icon') &&
            (args['style'] ?? '').contains('destructiveFilledButtonStyle('),
      ));
    }
  }
  return found;
}

/// The `path#label key` that names [action] in [_notConfirmations].
String _id(DialogAction action) =>
    '${action.path}#${action.labelKeys.firstWhere(_namesDestructiveVerb)}';

bool _destructive(DialogAction a) => a.labelKeys.any(_namesDestructiveVerb);

Set<String> _l10nKeys() => {
  for (final k
      in (jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, Object?>)
          .keys)
    if (!k.startsWith('@')) k,
};

void main() {
  group('every destructive dialog action is a destructive filled button', () {
    final l10nKeys = _l10nKeys();
    final actions = [
      for (final (path, source) in dartSources('lib'))
        if (!path.startsWith('lib/l10n/'))
          ...dialogActionsIn(path, source, l10nKeys),
    ];

    test('the scan reads the app', () {
      // Positive control: the pinned confirmations below whose label is a
      // destructive verb are found by discovery too, so the scan is reading
      // the dialogs, their actions and their labels.
      expect(l10nKeys, contains('commonDelete'));
      expect(actions.length, greaterThan(100));
      final discovered = {for (final a in actions.where(_destructive)) a.key};
      for (final key in [
        'confirm-delete-confirm',
        'calling-card-reset-confirm',
        'sync-device-remove-confirm',
      ]) {
        expect(
          discovered.any((k) => k.contains("'$key'")),
          isTrue,
          reason: '$key was not discovered',
        );
      }
    });

    test('a button that confirms a destructive action has the style', () {
      final offenders = [
        for (final a in actions)
          if (_destructive(a) &&
              !a.destructiveFilled &&
              !_notConfirmations.containsKey(_id(a)))
            '${a.path}:${a.line} ${a.key.isEmpty ? '(no key)' : a.key} '
                '${a.labelKeys.join(', ')}',
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'A dialog button that removes, resets, overwrites or discards '
            'data is a FilledButton with destructiveFilledButtonStyle. If it '
            'opens a confirmation rather than confirming, list it in '
            '_notConfirmations with the reason.',
      );
    });

    test('every entry in the allow-list is still a plain destructive '
        'button', () {
      final plain = {
        for (final a in actions)
          if (_destructive(a) && !a.destructiveFilled) _id(a),
      };
      for (final id in _notConfirmations.keys) {
        expect(plain, contains(id), reason: '$id: remove the stale entry');
      }
    });
  });

  test('the discovery scan reads a multi-line dialog, and ignores comments, '
      'strings and buttons outside actions', () {
    const keys = {'commonDelete', 'commonCancel', 'thingReset'};
    const source = '''
showDialog(builder: (ctx) => AlertDialog(
  content: TextButton(child: Text(l10n.commonDelete)), // not an action
  actions: [
    TextButton(onPressed: () {}, child: Text(l10n.commonCancel)),
    // TextButton(child: Text(l10n.commonDelete)),
    if (x) TextButton(
      key: const ValueKey('plain-delete'),
      onPressed: () => Navigator.of(ctx).pop(true),
      child: Text(
        label ?? l10n.commonDelete,
      ),
    ),
    FilledButton(
      key: const ValueKey('styled'),
      style: destructiveFilledButtonStyle(scheme),
      child: Text('a ) TextButton( l10n.thingReset'),
      onPressed: () {},
    ),
    FilledButton.tonal(
      style: destructiveFilledButtonStyle(scheme),
      child: Text(l10n.thingReset),
    ),
  ],
));
''';
    final found = dialogActionsIn('x.dart', source, keys);
    expect([for (final a in found) a.line], [4, 6, 13, 19]);
    expect(
      [
        for (final a in found.where(_destructive))
          (a.line, a.destructiveFilled),
      ],
      [(6, false), (19, false)],
    );
    expect(found[1].key, "const ValueKey('plain-delete')");
    expect(found[2].destructiveFilled, isTrue);
    expect(found[2].labelKeys, isEmpty);
    // Whole words of the key: a verb at the start counts; "Deleted" does not.
    expect(_namesDestructiveVerb('commonDelete'), isTrue);
    expect(_namesDestructiveVerb('clearAllConfirm'), isTrue);
    expect(_namesDestructiveVerb('recentlyDeletedRestore'), isFalse);
    expect(_namesDestructiveVerb('commonCancel'), isFalse);
  });

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
