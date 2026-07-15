import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/active_dialect_scope.dart';
import '../search/collection_data.dart';
import 'perform_card.dart';
import 'perform_wakelock.dart';

/// Full-screen, large-print performance view for a whole [Program]
/// (`docs/design/ux.md` §5; ROADMAP 5.2 — program navigation).
///
/// Walks the program's ordered *groups* ([Program.grouped]) — a primary slot
/// plus its trailing alternates count as one navigable position. Each slot
/// renders via the shared [PerformCard] (dance-backed slot) or [PerformTextCard]
/// (free-text-only slot), so this view stays identical to the single-dance
/// Perform view. Navigation is available via on-screen prev/next buttons, giant
/// edge hit zones, the keyboard (arrows / page keys), and a jump-to-slot
/// overview. When a group has alternates, a one-tap control swaps which member
/// is shown. Exit is a deliberate close button back to the editor.
///
/// In-view text size ([PerformSizeControls]) and the canonical ⇄ dialect toggle
/// ([PerformDialectToggle]) are shared across all slots so the caller sets them
/// once. This view is read-only: no destructive actions are reachable.
class PerformProgramScreen extends StatefulWidget {
  const PerformProgramScreen({
    super.key,
    required this.program,
    required this.data,
    required this.renderer,
    this.initialGroup = 0,
  });

  final Program program;
  final CollectionData data;
  final FigureRenderer renderer;

  /// Group index to open at (defaults to the first group).
  final int initialGroup;

  @override
  State<PerformProgramScreen> createState() => _PerformProgramScreenState();
}

class _PerformProgramScreenState extends State<PerformProgramScreen>
    with PerformWakelockMixin {
  late final List<ProgramSlotGroup> _groups = widget.program.grouped;

  /// Selected member within each group, indexing `[primary, ...alternates]`.
  late final List<int> _selectedMember = List<int>.filled(_groups.length, 0);

  final FocusNode _focusNode = FocusNode(debugLabel: 'perform-program');

  late int _groupIndex = widget.initialGroup.clamp(
    0,
    _groups.isEmpty ? 0 : _groups.length - 1,
  );

  double _textScale = kPerformDefaultScale;
  bool _canonicalView = false;

  /// Dark-stage high-contrast theme, on by default (`docs/design/ux.md` §5). In
  /// view only; persistence to Settings is a documented later follow-up.
  bool _stageMode = true;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _decreaseTextSize() {
    setState(() {
      _textScale = (_textScale - kPerformScaleStep).clamp(
        kPerformMinScale,
        double.infinity,
      );
    });
  }

  void _increaseTextSize() {
    setState(() => _textScale += kPerformScaleStep);
  }

  bool get _hasPrev => _groupIndex > 0;
  bool get _hasNext => _groupIndex < _groups.length - 1;

  void _goPrev() {
    if (!_hasPrev) return;
    setState(() => _groupIndex--);
    _announcePosition();
  }

  void _goNext() {
    if (!_hasNext) return;
    setState(() => _groupIndex++);
    _announcePosition();
  }

  void _announcePosition() {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Slot ${_groupIndex + 1} of ${_groups.length}',
      TextDirection.ltr,
    );
  }

  List<ProgramSlot> _membersOf(ProgramSlotGroup group) => [
    group.primary,
    ...group.alternates,
  ];

  void _swapAlternate() {
    final members = _membersOf(_groups[_groupIndex]);
    if (members.length < 2) return;
    setState(() {
      _selectedMember[_groupIndex] =
          (_selectedMember[_groupIndex] + 1) % members.length;
    });
    final slot = members[_selectedMember[_groupIndex]];
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Showing ${_slotLabel(slot)}',
      TextDirection.ltr,
    );
  }

  /// Display label for a slot: the dance title when it resolves, otherwise its
  /// free text (or a neutral fallback).
  String _slotLabel(ProgramSlot slot) {
    if (slot.danceId != null) {
      final dance = widget.data.dancesById[slot.danceId];
      if (dance != null) return dance.title;
    }
    final text = slot.text?.trim();
    if (text != null && text.isNotEmpty) return text;
    return 'Untitled slot';
  }

  List<String> _authorNamesFor(Dance dance) => [
    for (final id in dance.authorIds)
      if (widget.data.choreographerNames[id] != null)
        widget.data.choreographerNames[id]!,
  ];

  Future<void> _openJumpSheet() async {
    final target = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.builder(
            key: const ValueKey('perform-jump-list'),
            shrinkWrap: true,
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              final members = _membersOf(group);
              final subtitle = members.length > 1
                  ? '${members.length - 1} alternate'
                        '${members.length - 1 == 1 ? '' : 's'}'
                  : null;
              return ListTile(
                key: ValueKey('perform-jump-slot-$index'),
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(_slotLabel(group.primary)),
                subtitle: subtitle == null ? null : Text(subtitle),
                selected: index == _groupIndex,
                onTap: () => Navigator.of(sheetContext).pop(index),
              );
            },
          ),
        );
      },
    );
    if (target != null && mounted) {
      setState(() => _groupIndex = target);
      _announcePosition();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeDialect = ActiveDialectScope.of(context);
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;
    final canDecrease =
        _textScale - kPerformScaleStep >= kPerformMinScale - 1e-9;

    if (_groups.isEmpty) {
      // Defensive: the entry point hides the affordance for an empty program,
      // so this should not normally be reached.
      return PerformStageTheme(
        enabled: _stageMode,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('perform-program-exit'),
              tooltip: 'Exit performance view',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(widget.program.title),
          ),
          body: const Center(child: Text('This program has no slots.')),
        ),
      );
    }

    final group = _groups[_groupIndex];
    final members = _membersOf(group);
    final hasAlternates = members.length > 1;
    final memberIndex = _selectedMember[_groupIndex].clamp(
      0,
      members.length - 1,
    );
    final slot = members[memberIndex];

    return PerformStageTheme(
      enabled: _stageMode,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('perform-program-exit'),
            tooltip: 'Exit performance view',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(widget.program.title),
          actions: [
            IconButton(
              key: const ValueKey('perform-jump'),
              tooltip: 'Jump to slot',
              icon: const Icon(Icons.list),
              onPressed: _openJumpSheet,
            ),
            if (hasAlternates)
              IconButton(
                key: const ValueKey('perform-alt-swap'),
                tooltip: 'Show alternate',
                icon: const Icon(Icons.swap_horiz),
                onPressed: _swapAlternate,
              ),
            PerformSizeControls(
              canDecrease: canDecrease,
              onDecrease: _decreaseTextSize,
              onIncrease: _increaseTextSize,
            ),
            if (!isCanonicalDialect)
              PerformDialectToggle(
                canonical: _canonicalView,
                onChanged: (value) => setState(() => _canonicalView = value),
              ),
            PerformStageToggle(
              stageOn: _stageMode,
              onChanged: (value) => setState(() => _stageMode = value),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowRight): _goNext,
            const SingleActivator(LogicalKeyboardKey.arrowDown): _goNext,
            const SingleActivator(LogicalKeyboardKey.pageDown): _goNext,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): _goPrev,
            const SingleActivator(LogicalKeyboardKey.arrowUp): _goPrev,
            const SingleActivator(LogicalKeyboardKey.pageUp): _goPrev,
          },
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildCard(slot, dialect)),
                  // Giant edge hit zones (>=44pt) for touch/mouse. Accessibility
                  // and keyboard use go through the prev/next buttons, so these
                  // are excluded from semantics to avoid double-announcing.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 56,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        key: const ValueKey('perform-edge-prev'),
                        behavior: HitTestBehavior.translucent,
                        onTap: _hasPrev ? _goPrev : null,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 56,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        key: const ValueKey('perform-edge-next'),
                        behavior: HitTestBehavior.translucent,
                        onTap: _hasNext ? _goNext : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('perform-prev'),
                tooltip: 'Previous slot',
                icon: const Icon(Icons.chevron_left),
                onPressed: _hasPrev ? _goPrev : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Slot ${_groupIndex + 1} of ${_groups.length}',
                    key: const ValueKey('perform-position'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('perform-next'),
                tooltip: 'Next slot',
                icon: const Icon(Icons.chevron_right),
                onPressed: _hasNext ? _goNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(ProgramSlot slot, Dialect dialect) {
    if (slot.danceId != null) {
      final dance = widget.data.dancesById[slot.danceId];
      if (dance != null) {
        return PerformCard(
          dance: dance,
          renderer: widget.renderer,
          dialect: dialect,
          textScale: _textScale,
          authorNames: _authorNamesFor(dance),
        );
      }
    }
    // Free-text-only slot (or an unresolved dance id): a simple large-print
    // text card with no figures.
    return PerformTextCard(text: _slotLabel(slot), textScale: _textScale);
  }
}
