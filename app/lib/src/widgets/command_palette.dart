import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/reduce_motion_scope.dart';
import '../data/repositories_scope.dart';
import '../search/facet_labels.dart';
import 'skeleton.dart';

/// The kind of entity a [CommandResult] points at, so the shell knows which
/// section to switch to and which route to open.
enum CommandResultKind { dance, program }

/// A single selectable row in the [CommandPalette] — a dance or a program the
/// user can jump straight to.
class CommandResult {
  const CommandResult({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.icon = Icons.tag,
  });

  final CommandResultKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
}

/// Opens the global search / command palette as a modal, returning the chosen
/// [CommandResult] or `null` if dismissed. Wired to Ctrl/Cmd-K by the shell
/// (`docs/design/ux-modernization.md` §6). The palette itself only *selects*;
/// the caller performs navigation so it can also switch the active section.
Future<CommandResult?> showCommandPalette(BuildContext context) {
  return showDialog<CommandResult>(
    context: context,
    barrierLabel: 'Global search',
    builder: (_) => const CommandPalette(),
  );
}

/// Keyboard-first global search overlay. Type to filter dances and programs by
/// title; ↑/↓ move the highlight, Enter jumps to the highlighted result, Esc
/// closes. Every row pairs an icon with text (never color alone).
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// Max results shown per group so the list stays scannable.
  static const int perGroupLimit = 8;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _fieldFocus = FocusNode(debugLabel: 'command-palette-field');
  final _scrollController = ScrollController();
  final _query = ValueNotifier<String>('');

  List<CommandResult> _all = const [];
  List<CommandResult> _results = const [];
  List<GlobalKey> _rowKeys = const [];
  int _highlighted = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fieldFocus.onKeyEvent = _onFieldKey;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _fieldFocus.dispose();
    _scrollController.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repos = RepositoriesScope.of(context);
    final dances = await repos.dances.listAll();
    final programs = await repos.programs.listAll();
    if (!mounted) return;
    final all = <CommandResult>[
      for (final d in dances)
        CommandResult(
          kind: CommandResultKind.dance,
          id: d.id,
          title: d.title,
          subtitle: danceFormLabel(d.form),
          icon: danceFormIcon(d.form),
        ),
      for (final p in programs)
        CommandResult(
          kind: CommandResultKind.program,
          id: p.id,
          title: p.title,
          subtitle: 'Program',
          icon: Icons.event_note_outlined,
        ),
    ];
    setState(() {
      _all = all;
      _loading = false;
      _applyFilter(_query.value);
    });
  }

  void _applyFilter(String raw) {
    final q = raw.trim().toLowerCase();
    final dances = <CommandResult>[];
    final programs = <CommandResult>[];
    for (final r in _all) {
      if (q.isNotEmpty && !r.title.toLowerCase().contains(q)) continue;
      final bucket = r.kind == CommandResultKind.dance ? dances : programs;
      if (bucket.length < CommandPalette.perGroupLimit) bucket.add(r);
    }
    _results = [...dances, ...programs];
    _rowKeys = [for (var i = 0; i < _results.length; i++) GlobalKey()];
    _highlighted = _results.isEmpty
        ? 0
        : _highlighted.clamp(0, _results.length - 1);
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query.value = value;
      _highlighted = 0;
      _applyFilter(value);
    });
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activateHighlighted();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % _results.length;
      if (_highlighted < 0) _highlighted += _results.length;
    });
    _ensureHighlightedVisible();
  }

  void _ensureHighlightedVisible() {
    // Scroll the highlighted row into view via its element, so the maths is
    // robust to variable row heights (group headers differ from result rows).
    // Respect "Reduce motion" (ROADMAP G.7): jump instantly when it's on.
    final reduceMotion = ReduceMotionScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_highlighted < 0 || _highlighted >= _rowKeys.length) return;
      final context = _rowKeys[_highlighted].currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _activateHighlighted() {
    if (_highlighted < 0 || _highlighted >= _results.length) return;
    Navigator.of(context).pop(_results[_highlighted]);
  }

  void _activate(CommandResult result) => Navigator.of(context).pop(result);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      key: const ValueKey('command-palette'),
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                key: const ValueKey('command-palette-field'),
                focusNode: _fieldFocus,
                autofocus: true,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _activateHighlighted(),
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search dances and programs…',
                ),
              ),
            ),
            Flexible(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SkeletonResultRows(),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        key: const ValueKey('command-palette-empty'),
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _all.isEmpty
                ? 'Nothing to search yet.'
                : 'No matches for that search.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Flat, scrollable result list with a group label before the first item of
    // each kind so navigation index == visual order.
    final children = <Widget>[];
    CommandResultKind? lastKind;
    for (var i = 0; i < _results.length; i++) {
      final r = _results[i];
      if (r.kind != lastKind) {
        children.add(_GroupHeader(kind: r.kind));
        lastKind = r.kind;
      }
      children.add(
        KeyedSubtree(
          key: i < _rowKeys.length ? _rowKeys[i] : null,
          child: _ResultTile(
            result: r,
            highlighted: i == _highlighted,
            onTap: () => _activate(r),
          ),
        ),
      );
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: children,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.kind});

  final CommandResultKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = kind == CommandResultKind.dance ? 'Dances' : 'Programs';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.highlighted,
    required this.onTap,
  });

  final CommandResult result;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: highlighted
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: ListTile(
        key: ValueKey('command-result-${result.kind.name}-${result.id}'),
        dense: true,
        leading: Icon(result.icon),
        title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: result.subtitle == null ? null : Text(result.subtitle!),
        selected: highlighted,
        onTap: onTap,
      ),
    );
  }
}
