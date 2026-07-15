import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../search/collection_data.dart';
import 'perform_adjust_sheet.dart';
import 'perform_card.dart';
import 'perform_wakelock.dart';
import 'settings_screen.dart' show kAutoSizePerformKey;

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
    this.onProgramChanged,
  });

  final Program program;
  final CollectionData data;
  final FigureRenderer renderer;

  /// Group index to open at (defaults to the first group).
  final int initialGroup;

  /// Persists an in-event adjustment (`docs/design/ux.md` §5). Called with the
  /// new [Program] — a fresh `updatedAt` — after every reorder / insert / note /
  /// mark-performed edit made from the "adjust" sheet. When null (e.g. an
  /// unsaved draft with no owner to persist through), adjustments stay in-view
  /// only. The screen always updates its own live state first, so the reading
  /// view reflects the change regardless.
  final Future<void> Function(Program updated)? onProgramChanged;

  @override
  State<PerformProgramScreen> createState() => _PerformProgramScreenState();
}

class _PerformProgramScreenState extends State<PerformProgramScreen>
    with PerformWakelockMixin {
  /// The live working copy of the program. In-event adjustments mutate this and
  /// persist through [PerformProgramScreen.onProgramChanged]; navigation and
  /// grouping recompute from it so the reading view reflects edits immediately.
  late Program _program = widget.program;

  /// Cached navigable groups. [Program.grouped] walks the whole slot list and
  /// allocates a fresh unmodifiable list on every call, and the build/helpers
  /// read the groups several times per frame — so we recompute this only when
  /// [_program] actually changes (in [_applyProgram]) rather than on each read.
  late List<ProgramSlotGroup> _groups = _program.grouped;

  /// Selected member within each group, indexing `[primary, ...alternates]`.
  /// Rebuilt to match the group count whenever [_program] changes structurally.
  late List<int> _selectedMember = List<int>.filled(_groups.length, 0);

  final FocusNode _focusNode = FocusNode(debugLabel: 'perform-program');

  late int _groupIndex = widget.initialGroup.clamp(
    0,
    _groups.isEmpty ? 0 : _groups.length - 1,
  );

  double _textScale = kPerformDefaultScale;
  bool _canonicalView = false;

  /// Auto-size the card to fit the viewport (ROADMAP G.1). Initialised from the
  /// General setting (on by default) in [didChangeDependencies]; recomputes per
  /// slot as the shown dance/slot changes.
  bool _autoSize = true;
  bool _autoSizeLoaded = false;

  /// Ephemeral, in-view timing state (`docs/ROADMAP.md` §5.2). Timing is a
  /// display-only aid for the caller during an event: never persisted and never
  /// written back to the program (that is 5.3 territory).
  ///
  /// A single [Timer.periodic] (1s) drives both the running program clock and
  /// the per-slot elapsed. We accumulate whole seconds in [_elapsedSeconds]
  /// rather than diffing wall-clock time so the readouts advance deterministically
  /// under `tester.pump(Duration(...))`. The timer is independent of
  /// [PerformWakelockMixin] (which only toggles the wake-lock in initState/
  /// dispose), so the two do not interfere.
  Timer? _timer;
  int _elapsedSeconds = 0;

  /// Value of [_elapsedSeconds] when the current group was entered; the per-slot
  /// elapsed is the difference. Reset to "now" on every navigation.
  int _slotStartSeconds = 0;
  bool _paused = false;

  /// Dark-stage high-contrast theme, on by default (`docs/design/ux.md` §5). In
  /// view only; persistence to Settings is a documented later follow-up.
  bool _stageMode = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || !mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoSizeLoaded) return;
    _autoSizeLoaded = true;
    RepositoriesScope.of(context).settings.get(kAutoSizePerformKey).then((v) {
      if (!mounted) return;
      final enabled = v is bool ? v : true;
      if (enabled != _autoSize) setState(() => _autoSize = enabled);
    });
  }

  /// Marks the current group as freshly entered, zeroing the per-slot elapsed.
  void _resetSlotTimer() => _slotStartSeconds = _elapsedSeconds;

  void _togglePause() => setState(() => _paused = !_paused);

  int get _slotElapsedSeconds => _elapsedSeconds - _slotStartSeconds;

  /// `H:MM:SS` once past an hour, otherwise `MM:SS`.
  static String _formatDuration(int totalSeconds) {
    final seconds = totalSeconds % 60;
    final minutes = (totalSeconds ~/ 60) % 60;
    final hours = totalSeconds ~/ 3600;
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final mm = minutes.toString().padLeft(2, '0');
      return '$hours:$mm:$ss';
    }
    return '$minutes:$ss';
  }

  void _decreaseTextSize() {
    setState(() {
      // Using A-/A+ hands control back to the manual size (ROADMAP G.1).
      _autoSize = false;
      _textScale = (_textScale - kPerformScaleStep).clamp(
        kPerformMinScale,
        double.infinity,
      );
    });
  }

  void _increaseTextSize() {
    setState(() {
      _autoSize = false;
      _textScale += kPerformScaleStep;
    });
  }

  bool get _hasPrev => _groupIndex > 0;
  bool get _hasNext => _groupIndex < _groups.length - 1;

  void _goPrev() {
    if (!_hasPrev) return;
    setState(() {
      _groupIndex--;
      _resetSlotTimer();
    });
    _announcePosition();
  }

  void _goNext() {
    if (!_hasNext) return;
    setState(() {
      _groupIndex++;
      _resetSlotTimer();
    });
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
      _resetSlotTimer();
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
      setState(() {
        _groupIndex = target;
        _resetSlotTimer();
      });
      _announcePosition();
    }
  }

  /// The slot currently on screen (the selected member of the current group).
  ProgramSlot get _currentSlot {
    final members = _membersOf(_groups[_groupIndex]);
    return members[_selectedMember[_groupIndex].clamp(0, members.length - 1)];
  }

  /// Swaps in an edited [updated] program: recomputes grouping, keeps the view
  /// on the exact slot that was on screen (by id — the selected alternate too,
  /// not just its primary) so the caller keeps reading the same dance after a
  /// reorder/insert, and persists via [PerformProgramScreen.onProgramChanged].
  ///
  /// The per-slot timer keeps running while that slot is still on screen; it
  /// only resets when the previously visible slot is gone (e.g. removed), so
  /// timing (a 5.2 feature) is undisturbed by edits that leave it in place.
  void _applyProgram(Program updated, {String? announce}) {
    final prevSlotId = _groups.isEmpty ? null : _currentSlot.id;
    setState(() {
      _program = updated;
      _groups = _program.grouped;
      _selectedMember = List<int>.filled(_groups.length, 0);
      final maxIndex = _groups.isEmpty ? 0 : _groups.length - 1;
      var located = false;
      if (prevSlotId != null) {
        for (var gi = 0; gi < _groups.length; gi++) {
          final members = _membersOf(_groups[gi]);
          final mi = members.indexWhere((s) => s.id == prevSlotId);
          if (mi >= 0) {
            _groupIndex = gi;
            _selectedMember[gi] = mi;
            located = true;
            break;
          }
        }
      }
      if (!located) {
        _groupIndex = _groupIndex.clamp(0, maxIndex);
        _resetSlotTimer();
      }
    });
    if (announce != null && mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        announce,
        TextDirection.ltr,
      );
    }
    final onChanged = widget.onProgramChanged;
    if (onChanged != null) unawaited(onChanged(updated));
  }

  /// Applies [updated] and offers a one-tap SnackBar undo restoring the
  /// pre-edit program (the app-wide undo pattern), persisting either way.
  void _applyWithUndo(
    Program updated, {
    required String message,
    required String announce,
  }) {
    final previous = _program;
    _applyProgram(updated, announce: announce);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                _applyProgram(previous, announce: 'Adjustment undone'),
          ),
        ),
      );
  }

  /// Opens the non-destructive "adjust" sheet (`docs/design/ux.md` §5) over the
  /// reading view. The sheet edits a working copy (reorder remaining slots,
  /// insert a dance from quick-search, add an ad-hoc note, mark the current slot
  /// performed) and returns the edited program on close; we then apply it live
  /// with undo. Returning null (no change / dismissed) is a no-op.
  Future<void> _openAdjustSheet() async {
    final edited = await showModalBottomSheet<Program>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PerformAdjustSheet(
        program: _program,
        currentGroupIndex: _groupIndex,
        currentSlotId: _currentSlot.id,
        data: widget.data,
        dialect: _canonicalView
            ? Dialect.canonical
            : ActiveDialectScope.of(context),
      ),
    );
    if (edited == null || !mounted) return;
    _applyWithUndo(
      edited,
      message: 'Program adjusted.',
      announce: 'Program adjusted',
    );
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
              key: const ValueKey('perform-adjust'),
              tooltip: 'Adjust program',
              icon: const Icon(Icons.tune),
              onPressed: _openAdjustSheet,
            ),
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
            PerformAutoSizeToggle(
              autoSizeOn: _autoSize,
              onChanged: (value) => setState(() => _autoSize = value),
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
              _buildPauseButton(),
              IconButton(
                key: const ValueKey('perform-prev'),
                tooltip: 'Previous slot',
                icon: const Icon(Icons.chevron_left),
                onPressed: _hasPrev ? _goPrev : null,
              ),
              Expanded(
                child: Center(
                  child: Builder(
                    // Resolve the text style from a context *below*
                    // [PerformStageTheme] so the labels pick up the stage
                    // theme's on-surface color (readable on the dark
                    // BottomAppBar) when stage mode is on, rather than the
                    // outer ambient theme.
                    builder: (context) {
                      final textTheme = Theme.of(context).textTheme;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Slot ${_groupIndex + 1} of ${_groups.length}',
                            key: const ValueKey('perform-position'),
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          _buildTimingLine(slot, textTheme),
                        ],
                      );
                    },
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

  /// Pause/resume for the ephemeral timers. A single AT node carrying button
  /// role, name, tap action, and toggled (paused) state — same pattern as the
  /// stage toggle — so a caller who gets interrupted can freeze the clock.
  Widget _buildPauseButton() {
    final tooltip = _paused ? 'Resume timers' : 'Pause timers';
    return MergeSemantics(
      child: Semantics(
        toggled: _paused,
        child: IconButton(
          key: const ValueKey('perform-timer-pause'),
          tooltip: tooltip,
          isSelected: _paused,
          icon: const Icon(Icons.pause),
          selectedIcon: const Icon(Icons.play_arrow),
          onPressed: _togglePause,
        ),
      ),
    );
  }

  /// The running program clock, per-slot elapsed, and (when present) the
  /// planned slot length with a subtle over-run cue.
  ///
  /// AT reading is deliberately *on demand*: the whole line is one
  /// [Semantics] node with a composed [label] that a screen reader voices when
  /// focused, wrapping [ExcludeSemantics] visuals. A per-second live region
  /// would spam AT, so the value is read at focus time instead of on every tick.
  Widget _buildTimingLine(ProgramSlot slot, TextTheme textTheme) {
    final planned = slot.plannedMinutes;
    final slotElapsed = _slotElapsedSeconds;
    final isOver = planned != null && slotElapsed > planned * 60;
    final style = textTheme.bodyMedium;

    final label = StringBuffer(
      'Program time ${_formatDuration(_elapsedSeconds)}, '
      'slot time ${_formatDuration(slotElapsed)}',
    );
    if (planned != null) {
      label.write(', planned $planned ${planned == 1 ? 'minute' : 'minutes'}');
      if (isOver) label.write(', over planned');
    }
    if (_paused) label.write(', paused');

    return Semantics(
      label: label.toString(),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, size: 16),
            const SizedBox(width: 4),
            Text(
              _formatDuration(_elapsedSeconds),
              key: const ValueKey('perform-clock'),
              style: style,
            ),
            Text('  ·  ', style: style),
            Text(
              _formatDuration(slotElapsed),
              key: const ValueKey('perform-slot-elapsed'),
              style: style,
            ),
            if (planned != null) ...[
              Text('  ·  ', style: style),
              Text(
                'planned $planned min',
                key: const ValueKey('perform-planned'),
                style: style,
              ),
              if (isOver) ...[
                const SizedBox(width: 4),
                const Icon(Icons.timelapse, size: 16),
                Text(
                  ' over',
                  key: const ValueKey('perform-over'),
                  style: style,
                ),
              ],
            ],
          ],
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
          autoSize: _autoSize,
          authorNames: _authorNamesFor(dance),
        );
      }
    }
    // Free-text-only slot (or an unresolved dance id): a simple large-print
    // text card with no figures.
    return PerformTextCard(
      text: _slotLabel(slot),
      textScale: _textScale,
      autoSize: _autoSize,
    );
  }
}
