import 'package:flutter/material.dart';

import 'program_editor_screen.dart';
import 'program_summary_screen.dart';
import 'programs_list_screen.dart';

/// Responsive Programs shell (`docs/design/ux.md` §4), mirroring
/// [CollectionShell].
///
/// **Breakpoint: 900 logical pixels wide.**
/// - **Narrow (< 900 px):** [ProgramsListScreen] with push-navigation to the
///   read-focused [ProgramSummaryScreen] (a Perform-first summary), which in
///   turn opens the full-screen [ProgramEditorScreen] builder route on Edit.
/// - **Wide (≥ 900 px):** master-detail [Row] — a fixed 400 px list pane and a
///   lightweight **summary** pane for the selected program. Building/editing
///   opens the **full-screen** builder route (not embedded) so the builder's
///   slots | picker two-pane gets the full content width.
class ProgramsShell extends StatefulWidget {
  const ProgramsShell({super.key});

  static const double splitBreakpoint = 900;
  static const double listPaneWidth = 400;

  @override
  State<ProgramsShell> createState() => _ProgramsShellState();
}

class _ProgramsShellState extends State<ProgramsShell> {
  String? _selectedProgramId;
  final _listRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _listRefresh.dispose();
    super.dispose();
  }

  void _onSelectProgram(String id) {
    setState(() => _selectedProgramId = id);
  }

  /// Opens the full-screen builder route and refreshes the browse panes on
  /// return.
  Future<void> _openBuilder(BuildContext context, {String? programId}) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProgramEditorScreen(programId: programId),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      _listRefresh.value++;
      setState(() => _selectedProgramId = null);
    } else if (result != null) {
      _listRefresh.value++;
      setState(() => _selectedProgramId = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ProgramsShell.splitBreakpoint) {
          return _buildSplitPane();
        }
        // Narrow: single-pane list. Tapping a program pushes the read-focused
        // [ProgramSummaryScreen] (not the edit builder), mirroring the dance
        // side's narrow list → [DanceDetailScreen] flow.
        return const ProgramsListScreen();
      },
    );
  }

  Widget _buildSplitPane() {
    final selectedId = _selectedProgramId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: ProgramsShell.listPaneWidth,
          child: ScaffoldMessenger(
            child: ProgramsListScreen(
              onSelectProgram: _onSelectProgram,
              onCreateProgram: () => _openBuilder(context),
              selectedProgramId: _selectedProgramId,
              refreshTrigger: _listRefresh,
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: ScaffoldMessenger(
            child: selectedId != null
                ? ProgramSummaryPane(
                    key: ValueKey('summary-$selectedId'),
                    programId: selectedId,
                    refreshTrigger: _listRefresh,
                    onOpenBuilder: () =>
                        _openBuilder(context, programId: selectedId),
                    onDeleted: () {
                      _listRefresh.value++;
                      setState(() => _selectedProgramId = null);
                    },
                    onNavigateTo: (id) {
                      _listRefresh.value++;
                      setState(() => _selectedProgramId = id);
                    },
                    onProgramMutated: () => _listRefresh.value++,
                  )
                : const _EmptyEditorPane(),
          ),
        ),
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
