// Typed text is never lost (#2219, #2236): every dialog or bottom sheet that
// holds a text field keeps its text through a stray tap outside, Escape and
// Back, by wrapping its content in `DirtyDialogGuard` (a small input dialog)
// or `DiscardChangesGuard` (an editor that asks first). Pre-release audit
// finding F-02 found six surfaces added later without either.
//
// This scan reads every file under lib/ and fails on any route opener
// (`showDialog`, `showModalBottomSheet` and the rest in [_openers]) whose
// content holds a text field but no guard. "Content" is what the opener
// builds, followed through the code that builds it:
//
// - the opener's own arguments;
// - every app class they name (a widget, and the `State` of a stateful one),
//   and every class those name in turn;
// - every method of the enclosing class, top-level function or local
//   variable or function they call or read by name.
//
// Comments and string literals are blanked before anything is read, and every
// match allows whitespace and line breaks wherever Dart does, so a reformat
// cannot hide a field. The arguments of a dialog opened from inside another
// are left out of the outer one's content, so a guarded confirm dialog cannot
// vouch for the editor that opens it. A sheet guarded by
// `DiscardChangesGuard` must also turn dragging off: a swipe pops the route
// directly, past the guard. And a route opener used other than by calling it
// (`final open = showDialog;`) fails outright, since it could then be called
// under a name this scan does not know.
//
// The scan has its own positive controls below ("the scan flags …"): each
// shape it must catch is fed to it as a small source, so a scan that silently
// stopped matching would fail them too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-entry surfaces that are exempt, by `file#member`, where member is the
/// declaration (method, function or class) the opener call sits in. Each says
/// why the guard does not apply there.
const _exempt = <String, String>{
  // Search and filter boxes: what is typed is a query, and the choice it
  // finds takes effect the moment it is picked.
  'lib/src/screens/perform_adjust_sheet.dart#_openInsertPicker':
      'the Perform insert picker: its text field searches the collection',
  'lib/src/screens/perform_adjust_sheet.dart#_showSwap':
      'the Perform swap sheet: its text field searches for a replacement',
  'lib/src/screens/settings/defaults_section.dart#_openAddMoveDialog':
      'a move picker: the text finds a move, and choosing one closes it',
  'lib/src/screens/settings/library_manager_list.dart#showLibraryMergePicker':
      'a merge-target picker: its text field filters the list',
  'lib/src/screens/settings/program_templates_screen.dart#_addDance':
      'a dance picker: its text field searches the collection',
  'lib/src/widgets/add_to_program_sheet.dart#showAddToProgramSheet':
      'a program picker: its text field filters the programs',
  'lib/src/widgets/command_palette.dart#showCommandPalette':
      'the command palette: its text field filters the commands',
  'lib/src/widgets/program_event_rules.dart#showProgramRulesPicker':
      'a rule picker: its text field filters the rules',
  'lib/src/screens/program_editor_screen.dart#_openPickerSheet':
      'the program editor dance picker: its text field searches the '
      'collection',
  'lib/src/screens/program_editor_screen.dart#_showDancePickerSheet':
      'the program editor dance picker for a slot: its text field searches '
      'the collection',
  // Read-only previews: the scan reaches a text field through the dance
  // detail screen's own editing dialogs, which are checked where they open.
  'lib/src/screens/program_editor_screen.dart#_openSavedPreviewSheet':
      'a read-only dance preview',
  'lib/src/screens/program_editor_screen.dart#_openOnlinePreviewSheet':
      'a read-only online dance preview',
  // Known gaps, not yet fixed: each loses typed text today.
  'lib/src/screens/perform_program_screen.dart#_openAdjustSheet':
      'KNOWN GAP: the Perform adjust sheet keeps its edits when dismissed, '
      'but an ad-hoc note typed and not yet added is lost',
};

void main() {
  group('the scan flags', () {
    test('an unguarded dialog split across lines, through its State', () {
      final findings = _scan({
        'lib/a.dart': '''
Future<String?> ask(BuildContext context) => showDialog
    <String>
    (
  context: context,
  builder: (_) =>
      const _NameDialog(),
);
class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}
class _NameDialogState extends State<_NameDialog> {
  @override
  Widget build(BuildContext context) => AlertDialog(
    content: TextField
        (controller: _c),
  );
}
''',
      });
      expect(findings, ['lib/a.dart#ask: no guard']);
    });

    test('nothing once that dialog is guarded', () {
      final findings = _scan({
        'lib/a.dart': '''
Future<String?> ask(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _NameDialog(),
);
class _NameDialog extends StatefulWidget {
  State<_NameDialog> createState() => _NameDialogState();
}
class _NameDialogState extends State<_NameDialog> {
  Widget build(BuildContext context) => DirtyDialogGuard(
    listenable: _c,
    isDirty: () => _c.text.isNotEmpty,
    child: AlertDialog(content: TextField(controller: _c)),
  );
}
''',
      });
      expect(findings, isEmpty);
    });

    test('a field held in a local variable', () {
      final findings = _scan({
        'lib/a.dart': '''
class Page extends StatelessWidget {
  void _rename(BuildContext context) {
    final field = TextField(controller: _c);
    final dialog = AlertDialog(content: field);
    showDialog<void>(context: context, builder: (_) => dialog);
  }
}
''',
      });
      expect(findings, ['lib/a.dart#_rename: no guard']);
    });

    test('a field built by a method of the enclosing class', () {
      final findings = _scan({
        'lib/a.dart': '''
class Page extends StatelessWidget {
  Widget _content() => const TextField();
  void _rename(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(content: _content()),
    );
  }
}
''',
      });
      expect(findings, ['lib/a.dart#_rename: no guard']);
    });

    test('a field behind a typedef, in another file', () {
      final findings = _scan({
        'lib/a.dart': 'typedef Box = TextField;',
        'lib/b.dart': '''
void open(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AlertDialog(content: Box()),
);
''',
      });
      expect(findings, ['lib/b.dart#open: no guard']);
    });

    test('a field whose guard is only in a dialog it opens', () {
      final findings = _scan({
        'lib/a.dart': '''
void open(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => AlertDialog(
    content: const TextField(),
    actions: [
      TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => DirtyDialogGuard(child: const SizedBox()),
        ),
      ),
    ],
  ),
);
''',
      });
      expect(findings, ['lib/a.dart#open: no guard']);
    });

    test('a field whose only guard is deep inside a widget it shows', () {
      final findings = _scan({
        'lib/a.dart': '''
void open(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AlertDialog(content: _Body()),
);
class _Body extends StatelessWidget {
  Widget build(BuildContext context) =>
      Column(children: [TextField(), _Row()]);
}
class _Row extends StatelessWidget {
  Widget build(BuildContext context) =>
      DiscardChangesGuard(dirty: false, child: SizedBox());
}
''',
      });
      expect(findings, ['lib/a.dart#open: no guard']);
    });

    test('nothing for a dialog that only opens a page with a field', () {
      final findings = _scan({
        'lib/a.dart': '''
void open(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => AlertDialog(
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TextField()),
        ),
      ),
    ],
  ),
);
''',
      });
      expect(findings, isEmpty);
    });

    test('a guarded sheet that can still be swiped away', () {
      final findings = _scan({
        'lib/a.dart': '''
void open(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => DiscardChangesGuard(dirty: true, child: TextField()),
);
''',
      });
      expect(findings, [
        'lib/a.dart#open: a guarded sheet must set enableDrag: false',
      ]);
    });

    test('nothing for a guarded sheet with dragging off', () {
      final findings = _scan({
        'lib/a.dart': '''
void open(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  enableDrag: false,
  builder: (_) => DiscardChangesGuard(dirty: true, child: TextField()),
);
''',
      });
      expect(findings, isEmpty);
    });

    test('a route opener under another name', () {
      final findings = _scan({
        'lib/a.dart': '''
import 'package:flutter/material.dart' show showDialog;
void open(BuildContext context) {
  final show = showDialog;
  show(context: context, builder: (_) => const TextField());
}
''',
      });
      expect(findings, ['lib/a.dart#open: showDialog used other than called']);
    });

    test('nothing for a field named only in comments and strings', () {
      final findings = _scan({
        'lib/a.dart': r'''
/// Unlike a [TextField] dialog, this one only confirms.
void open(BuildContext context) => showDialog<void>(
  context: context,
  // TextField(
  builder: (_) => AlertDialog(
    content: Text('TextField( ${'TextFormField('} """'),
  ),
);
''',
      });
      expect(findings, isEmpty);
    });
  });

  test('every text-entry dialog and sheet under lib/ keeps typed text', () {
    final sources = <String, String>{
      for (final entity in Directory('lib').listSync(recursive: true))
        // lib/l10n is generated strings, and holds no widgets.
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.replaceAll(r'\', '/').startsWith('lib/l10n/'))
          entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
    };
    expect(sources, isNotEmpty);
    final findings = _scan(sources);
    final exempted = {
      for (final f in findings)
        if (_exempt.containsKey(f.split(':').first)) f.split(':').first,
    };
    expect(
      findings.where((f) => !_exempt.containsKey(f.split(':').first)),
      isEmpty,
      reason:
          'wrap the content in DirtyDialogGuard (a small input dialog) or '
          'DiscardChangesGuard (an editor), as #2219 and #2236 did',
    );
    expect(
      exempted,
      _exempt.keys.toSet(),
      reason: 'an exemption that no longer matches anything is stale',
    );
  });
}

/// The calls that open a dialog or sheet route.
const _openers = [
  'showDialog',
  'showAdaptiveDialog',
  'showGeneralDialog',
  'showCupertinoDialog',
  'showCupertinoModalPopup',
  'showModalBottomSheet',
  'showBottomSheet',
  'DialogRoute',
  'RawDialogRoute',
  'ModalBottomSheetRoute',
];

const _sheetOpeners = {
  'showModalBottomSheet',
  'showBottomSheet',
  'ModalBottomSheetRoute',
};

final _textEntry = RegExp(
  r'\b(?:TextField|TextFormField|CupertinoTextField|EditableText)\b',
);
final _guard = RegExp(r'\b(?:DirtyDialogGuard|DiscardChangesGuard)\b');
final _openerName = RegExp('\\b(?:${_openers.join('|')})\\b');

/// Route openers, and the routes of full pages: what either builds is not
/// part of a dialog that opens it.
final _routeName = RegExp(
  '\\b(?:${[..._openers, 'MaterialPageRoute', 'CupertinoPageRoute', 'PageRouteBuilder'].join('|')})\\b',
);
final _identifier = RegExp(r'[A-Za-z_$][\w$]*');

/// Findings as `file#member: problem`, sorted.
List<String> _scan(Map<String, String> sources) {
  final files = {
    for (final MapEntry(:key, :value) in sources.entries)
      key: _File(key, value),
  };
  final index = _Index(files.values);
  final findings = <String>{};
  for (final file in files.values) {
    for (final m in _openerName.allMatches(file.code)) {
      final member = file.memberAt(m.start);
      final where = '${file.path}#${member?.name ?? '(top level)'}';
      final open = file.callParen(m.end);
      if (open == null) {
        if (!file.inDirective(m.start)) {
          findings.add('$where: ${m[0]} used other than called');
        }
        continue;
      }
      final close = file.closing(open);
      final reach = index.reach(file, open + 1, close, member);
      if (!reach.text) continue;
      if (!reach.guard) {
        findings.add('$where: no guard');
      } else if (_sheetOpeners.contains(m[0]) &&
          reach.discardGuard &&
          !RegExp(
            r'\benableDrag\s*:\s*false\b',
          ).hasMatch(file.code.substring(open, close))) {
        findings.add('$where: a guarded sheet must set enableDrag: false');
      }
    }
  }
  return findings.toList()..sort();
}

/// A declaration: a class, mixin, extension or typedef (a type), or a
/// function, method, getter or local variable (a member).
class _Decl {
  _Decl(
    this.file,
    this.name,
    this.start,
    this.end, {
    this.parent,
    this.local = false,
    this.type = false,
  });

  /// A class, mixin, extension, enum or typedef.
  final bool type;

  /// A local variable or function: its own references resolve in [parent].
  final bool local;

  final _File file;
  final String name;
  final int start;
  final int end;

  /// The type a member belongs to, or null at the top level.
  final _Decl? parent;

  /// A local's references resolve in its [parent], so the same local read
  /// from two contexts is two declarations.
  @override
  bool operator ==(Object other) =>
      other is _Decl &&
      other.file == file &&
      other.start == start &&
      other.end == end &&
      other.local == local &&
      (!local || other.parent == parent);

  @override
  int get hashCode => Object.hash(file, start, end, local ? parent : null);
}

class _File {
  _File(this.path, String source) : code = _blank(source) {
    _depth = List<int>.filled(code.length + 1, 0);
    var d = 0;
    for (var i = 0; i < code.length; i++) {
      _depth[i] = d;
      final c = code[i];
      if (c == '(' || c == '[' || c == '{') d++;
      if (c == ')' || c == ']' || c == '}') d--;
    }
    _depth[code.length] = d;
    _readTypes();
    members.addAll(_membersIn(0, code.length, 0, null));
    for (final type in types) {
      final body = code.indexOf('{', type.start);
      if (body < 0 || body > type.end) continue;
      members.addAll(_membersIn(body + 1, type.end, _depth[body] + 1, type));
    }
  }

  final String path;

  /// The source with comments and string literals blanked to spaces, so
  /// offsets match the source.
  final String code;
  late final List<int> _depth;
  final types = <_Decl>[];
  final members = <_Decl>[];

  /// The `State` classes, by the widget they are the state of.
  final statesOf = <String, List<_Decl>>{};

  void _readTypes() {
    final header = RegExp(
      r'\b(class|mixin|extension|enum)\s+([A-Za-z_$][\w$]*)?([^{;]*)\{',
    );
    for (final m in header.allMatches(code)) {
      if (_depth[m.start] != 0) continue;
      final open = m.end - 1;
      final type = _Decl(this, m[2] ?? '', m.start, closing(open), type: true);
      types.add(type);
      final state = RegExp(
        r'\bextends\s+State\s*<\s*([A-Za-z_$][\w$]*)',
      ).firstMatch(m[3]!);
      if (state != null) (statesOf[state[1]!] ??= []).add(type);
    }
    final typedef = RegExp(r'\btypedef\s+([A-Za-z_$][\w$]*)[^;]*;');
    for (final m in typedef.allMatches(code)) {
      if (_depth[m.start] == 0) {
        types.add(_Decl(this, m[1]!, m.start, m.end, type: true));
      }
    }
  }

  static const _notNames = {
    'if', 'for', 'while', 'switch', 'catch', 'return', 'assert', 'super', //
    'this', 'await', 'throw', 'new', 'const', 'when', 'on', 'in', 'is',
  };

  /// The functions, methods, getters and variables declared at [depth] in
  /// [start]..[end].
  List<_Decl> _membersIn(int start, int end, int depth, _Decl? parent) {
    final found = <_Decl>[];
    final name = RegExp(r'\b([A-Za-z_$][\w$]*)\s*(?=[(=]|=>|\{|;|,)');
    for (final m in name.allMatches(code.substring(start, end))) {
      final at = start + m.start;
      if (_depth[at] != depth) continue;
      final id = m[1]!;
      if (_notNames.contains(id)) continue;
      var i = start + m.end;
      if (code[i] == '(') {
        // A function or method: its parameters, then a body.
        i = _skipSpace(closing(i) + 1);
        for (final word in ['async*', 'async', 'sync*']) {
          if (code.startsWith(word, i)) i = _skipSpace(i + word.length);
        }
        if (code.startsWith('{', i)) {
          found.add(_Decl(this, id, at, closing(i), parent: parent));
        } else if (code.startsWith('=>', i)) {
          found.add(_Decl(this, id, at, _statementEnd(i), parent: parent));
        }
      } else if (code.startsWith('=>', i) || code.startsWith('{', i)) {
        // A getter.
        final before = code.substring(at < start + 16 ? start : at - 16, at);
        if (!RegExp(r'\bget\s+$').hasMatch(before)) {
          continue;
        }
        final end = code[i] == '{' ? closing(i) : _statementEnd(i);
        found.add(_Decl(this, id, at, end, parent: parent));
      } else if (code[i] == '=' && !code.startsWith('==', i)) {
        // A variable with an initializer.
        found.add(_Decl(this, id, at, _statementEnd(i), parent: parent));
      }
    }
    return found;
  }

  int _skipSpace(int i) {
    while (i < code.length && code[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  /// The end of the expression starting at [i]: the next `;` or `,` at the
  /// same depth, or the bracket closing it.
  int _statementEnd(int i) {
    final depth = _depth[i];
    for (var j = i; j < code.length; j++) {
      if (_depth[j] < depth) return j;
      if (_depth[j] == depth && (code[j] == ';' || code[j] == ',')) return j;
    }
    return code.length;
  }

  /// The offset just past the bracket matching the one at [open].
  int closing(int open) {
    final depth = _depth[open];
    for (var j = open + 1; j < code.length; j++) {
      if (_depth[j + 1] == depth) return j + 1;
    }
    return code.length;
  }

  /// The `(` opening a call of the name ending at [i], past any type
  /// arguments and line breaks, or null when the name is not called.
  int? callParen(int i) {
    i = _skipSpace(i);
    if (i < code.length && code[i] == '<') {
      var angle = 0;
      for (; i < code.length; i++) {
        if (code[i] == '<') angle++;
        if (code[i] == '>' && --angle == 0) break;
      }
      i = _skipSpace(i + 1);
    }
    return i < code.length && code[i] == '(' ? i : null;
  }

  /// Whether the identifier at [start]..[end] names a named argument
  /// (`title: …`) rather than reading something.
  bool isArgumentLabel(int start, int end) {
    final after = _skipSpace(end);
    if (after >= code.length || code[after] != ':') return false;
    var before = start - 1;
    while (before >= 0 && code[before].trim().isEmpty) {
      before--;
    }
    return before >= 0 && (code[before] == '(' || code[before] == ',');
  }

  bool inDirective(int i) {
    final lineStart = code.lastIndexOf('\n', i) + 1;
    return RegExp(
      r'^\s*(?:import|export)\b',
    ).hasMatch(code.substring(lineStart, i));
  }

  /// The innermost function, method or type around [i].
  _Decl? memberAt(int i) {
    _Decl? best;
    for (final list in [members, types]) {
      for (final d in list) {
        if (d.start <= i && i < d.end) {
          if (best == null || d.start >= best.start) best = d;
        }
      }
    }
    return best;
  }

  /// [start]..[end] with the arguments of every route opener and page route
  /// strictly inside it blanked: a dialog opened from this one is checked on
  /// its own, and a page it opens is not part of it.
  String without(int start, int end) {
    final out = StringBuffer();
    var at = start;
    for (final (open, close) in openerArgs) {
      if (open <= start || close > end || open < at) continue;
      out
        ..write(code.substring(at, open))
        ..write(' ' * (close - open));
      at = close;
    }
    out.write(code.substring(at, end));
    return out.toString();
  }

  /// The argument list of every route opener call and page route, as (`(`,
  /// past `)`).
  late final List<(int, int)> openerArgs = [
    for (final m in _routeName.allMatches(code))
      if (callParen(m.end) case final open?) (open, closing(open)),
  ];

  late final Map<String, List<_Decl>> membersByName = () {
    final byName = <String, List<_Decl>>{};
    for (final d in members) {
      (byName[d.name] ??= []).add(d);
    }
    return byName;
  }();

  /// Every variable initialised or function declared, at any depth, by name:
  /// the locals a member's references can resolve to.
  late final Map<String, List<_Decl>> locals = () {
    final byName = <String, List<_Decl>>{};
    final decl = RegExp(
      r'\b([A-Za-z_$][\w$]*)\s*(?:=(?![=>])|\([^()]*\)\s*(?:async\s*)?(?:=>|\{))',
    );
    for (final m in decl.allMatches(code)) {
      final name = m[1]!;
      if (_notNames.contains(name)) continue;
      final eq = code.indexOf(RegExp(r'=>|=|\{'), m.start + name.length);
      final end = code[eq] == '{' ? closing(eq) : _statementEnd(eq);
      (byName[name] ??= []).add(_Decl(this, name, m.start, end, local: true));
    }
    return byName;
  }();
}

/// Finds the code an opener's arguments reach.
class _Index {
  _Index(Iterable<_File> files) {
    for (final file in files) {
      for (final type in file.types) {
        final key = type.name.startsWith('_')
            ? '${file.path}#${type.name}'
            : type.name;
        (_types[key] ??= []).add(type);
      }
    }
  }

  final _types = <String, List<_Decl>>{};
  final _nodes = <_Decl, _Node>{};

  /// What the text [start]..[end] of [file] reaches, from inside [context]:
  /// whether a text field, a guard, and a [DiscardChangesGuard] are in it.
  ({bool text, bool guard, bool discardGuard}) reach(
    _File file,
    int start,
    int end,
    _Decl? context,
  ) {
    final root = _node(file, start, end, context);
    // The guard has to be where the dialog is built: in the opener's
    // arguments, the code they call, or the widget they name (and its State),
    // not in some class that widget reaches further down. A field counts
    // however deep it is.
    var guard = false, discard = false;
    final near = <(_Decl?, int)>{};
    final nearQueue = [(root, null as _Decl?, 0)];
    while (nearQueue.isNotEmpty) {
      final (node, _, hops) = nearQueue.removeLast();
      guard |= node.guard;
      discard |= node.discardGuard;
      for (final next in node.memberRefs) {
        if (near.add((next, hops))) nearQueue.add((_of(next), next, hops));
      }
      if (hops > 0) continue;
      for (final next in node.typeRefs) {
        if (near.add((next, 1))) nearQueue.add((_of(next), next, 1));
      }
    }
    var text = false;
    final seen = <_Decl>{};
    final queue = [root];
    while (queue.isNotEmpty && !text) {
      final node = queue.removeLast();
      text |= node.text;
      for (final next in [...node.memberRefs, ...node.typeRefs]) {
        if (seen.add(next)) queue.add(_of(next));
      }
    }
    return (text: text, guard: guard, discardGuard: discard);
  }

  _Node _of(_Decl decl) => _nodes[decl] ??= _nodeOf(decl);

  _Node _nodeOf(_Decl decl) =>
      _node(decl.file, decl.start, decl.end, decl.local ? decl.parent : decl);

  _Node _node(_File file, int start, int end, _Decl? context) {
    final text = file.without(start, end);
    final memberRefs = <_Decl>{};
    final typeRefs = <_Decl>{};
    for (final m in _identifier.allMatches(text)) {
      final at = start + m.start;
      if (at > 0 && file.code[at - 1] == '.') continue;
      if (file.isArgumentLabel(at, at + m[0]!.length)) continue;
      for (final decl in _resolve(file, m[0]!, context)) {
        if (decl.type) {
          typeRefs
            ..add(decl)
            ..addAll(decl.file.statesOf[decl.name] ?? const <_Decl>[]);
        } else {
          memberRefs.add(decl);
        }
      }
    }
    return _Node(
      text: _textEntry.hasMatch(text),
      guard: _guard.hasMatch(text),
      discardGuard: text.contains('DiscardChangesGuard'),
      memberRefs: memberRefs,
      typeRefs: typeRefs,
    );
  }

  Iterable<_Decl> _resolve(_File file, String name, _Decl? context) sync* {
    if (RegExp(r'^_?[A-Z]').hasMatch(name)) {
      yield* _types[name.startsWith('_') ? '${file.path}#$name' : name] ??
          const <_Decl>[];
      return;
    }
    // Members of the enclosing type, and the file's top level.
    for (final d in file.membersByName[name] ?? const <_Decl>[]) {
      final ofType =
          d.parent != null &&
          context != null &&
          d.parent!.start <= context.start &&
          context.end <= d.parent!.end;
      if (ofType || d.parent == null) yield d;
    }
    // Locals declared inside the context.
    if (context == null) return;
    for (final d in file.locals[name] ?? const <_Decl>[]) {
      if (d.start >= context.start && d.end <= context.end) {
        yield _Decl(file, name, d.start, d.end, parent: context, local: true);
      }
    }
  }
}

class _Node {
  _Node({
    required this.text,
    required this.guard,
    required this.discardGuard,
    required this.memberRefs,
    required this.typeRefs,
  });

  final bool text;
  final bool guard;
  final bool discardGuard;

  /// The functions, methods, getters and variables this code reads.
  final Set<_Decl> memberRefs;

  /// The classes and typedefs this code names, with their `State` classes.
  final Set<_Decl> typeRefs;
}

/// [source] with comments and the bodies of string literals (interpolations
/// included) replaced by spaces, line breaks kept.
String _blank(String source) {
  final out = source.split('');
  final n = source.length;
  void blank(int from, int to) {
    for (var i = from; i < to && i < n; i++) {
      if (out[i] != '\n') out[i] = ' ';
    }
  }

  late int Function(int i, {bool untilBrace}) code;

  int stringEnd(int i, {required bool raw}) {
    final q = source[i];
    final triple = source.startsWith(q * 3, i);
    i += triple ? 3 : 1;
    while (i < n) {
      if (!raw && source[i] == r'\') {
        i += 2;
      } else if (!raw && source.startsWith(r'${', i)) {
        i = code(i + 2, untilBrace: true);
      } else if (triple ? source.startsWith(q * 3, i) : source[i] == q) {
        return i + (triple ? 3 : 1);
      } else {
        i++;
      }
    }
    return n;
  }

  code = (int i, {bool untilBrace = false}) {
    var depth = 0;
    while (i < n) {
      final c = source[i];
      if (source.startsWith('//', i)) {
        var end = source.indexOf('\n', i);
        if (end < 0) end = n;
        blank(i, end);
        i = end;
      } else if (source.startsWith('/*', i)) {
        var nest = 0;
        var j = i;
        while (j < n) {
          if (source.startsWith('/*', j)) {
            nest++;
            j += 2;
          } else if (source.startsWith('*/', j)) {
            j += 2;
            if (--nest == 0) break;
          } else {
            j++;
          }
        }
        blank(i, j);
        i = j;
      } else if (c == "'" || c == '"') {
        final raw =
            i > 0 &&
            (source[i - 1] == 'r' || source[i - 1] == 'R') &&
            (i < 2 || !RegExp(r'[\w$]').hasMatch(source[i - 2]));
        final end = stringEnd(i, raw: raw);
        blank(i + 1, end - 1);
        i = end;
      } else if (untilBrace && c == '{') {
        depth++;
        i++;
      } else if (untilBrace && c == '}') {
        if (depth == 0) return i + 1;
        depth--;
        i++;
      } else {
        i++;
      }
    }
    return n;
  };

  code(0);
  return out.join();
}
