import 'package:flutter/material.dart';

import 'program_editor_screen.dart';
import 'programs_list_screen.dart';

/// Responsive Programs shell (`docs/design/ux.md` §4), mirroring
/// [CollectionShell].
///
/// **Breakpoint: 900 logical pixels wide.**
/// - **Narrow (< 900 px):** [ProgramsListScreen] with push-navigation to the
///   [ProgramEditorScreen].
/// - **Wide (≥ 900 px):** master-detail [Row] — a fixed 400 px list pane and a
///   flexible editor pane showing the selected/new program, or an empty-state
///   placeholder.
class ProgramsShell extends StatefulWidget {
  const ProgramsShell({super.key});

  static const double splitBreakpoint = 900;
  static const double listPaneWidth = 400;

  @override
  State<ProgramsShell> createState() => _ProgramsShellState();
}

class _ProgramsShellState extends State<ProgramsShell> {
  String? _selectedProgramId;

  /// True when the editor pane should host a new-program create flow.
  bool _creating = false;

  final _listRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _listRefresh.dispose();
    super.dispose();
  }

  void _onSelectProgram(String id) {
    setState(() {
      _selectedProgramId = id;
      _creating = false;
    });
  }

  void _onCreateProgram() {
    setState(() {
      _selectedProgramId = null;
      _creating = true;
    });
  }

  void _onSaved(String id) {
    _listRefresh.value++;
    setState(() {
      _selectedProgramId = id;
      _creating = false;
    });
  }

  void _onDeleted() {
    _listRefresh.value++;
    setState(() {
      _selectedProgramId = null;
      _creating = false;
    });
  }

  void _onNavigateTo(String id) {
    _listRefresh.value++;
    setState(() {
      _selectedProgramId = id;
      _creating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ProgramsShell.splitBreakpoint) {
          return _buildSplitPane();
        }
        return const ProgramsListScreen();
      },
    );
  }

  Widget _buildSplitPane() {
    final selectedId = _selectedProgramId;
    final Widget detail;
    if (_creating) {
      detail = ProgramEditorScreen(
        // A fresh key per create session so the form resets cleanly.
        key: const ValueKey('editor-new'),
        onSaved: _onSaved,
        onDeleted: _onDeleted,
        onNavigateTo: _onNavigateTo,
      );
    } else if (selectedId != null) {
      detail = ProgramEditorScreen(
        key: ValueKey('editor-$selectedId'),
        programId: selectedId,
        onSaved: _onSaved,
        onDeleted: _onDeleted,
        onNavigateTo: _onNavigateTo,
      );
    } else {
      detail = const _EmptyEditorPane();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: ProgramsShell.listPaneWidth,
          child: ScaffoldMessenger(
            child: ProgramsListScreen(
              onSelectProgram: _onSelectProgram,
              onCreateProgram: _onCreateProgram,
              selectedProgramId: _selectedProgramId,
              refreshTrigger: _listRefresh,
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: ScaffoldMessenger(child: detail)),
      ],
    );
  }
}

class _EmptyEditorPane extends StatelessWidget {
  const _EmptyEditorPane();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a program',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a program from the list, or create a new one.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
