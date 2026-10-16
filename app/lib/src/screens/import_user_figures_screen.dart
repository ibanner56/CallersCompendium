import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What the user chose on [ImportUserFiguresScreen], by each shared figure's
/// id as it came.
@immutable
class UserFigureImportChoices {
  const UserFigureImportChoices({
    this.add = const {},
    this.useTheirs = const {},
  });

  /// Figures to add: new ones, and copies.
  final Set<String> add;

  /// Figures that differ from the user's own, to replace with the sender's.
  final Set<String> useTheirs;

  bool get isEmpty => add.isEmpty && useTheirs.isEmpty;
}

/// The opt-in step, after a shared file is imported, that offers the figures
/// of the sender's own its dances use (#1023, maintainer decision 3; plan
/// C12), as [planUserFigureImport] sorted them:
/// - **new** ones and **copies** (whose id this device has used before) to
///   add, each ticked;
/// - ones **different from yours**, to keep yours (the default) or use theirs;
/// - ones **already in your Glossary**, listed only.
///
/// A figure whose name is taken here says so ([nameTaken]): it is added all
/// the same, and the Glossary marks it Rename needed.
///
/// Pops a [UserFigureImportChoices]; empty when the user skips.
class ImportUserFiguresScreen extends StatefulWidget {
  const ImportUserFiguresScreen({
    super.key,
    required this.items,
    this.nameTaken = const {},
  });

  final List<UserFigureImportItem> items;

  /// The ids, as they came, of figures whose name is taken here.
  final Set<String> nameTaken;

  @override
  State<ImportUserFiguresScreen> createState() =>
      _ImportUserFiguresScreenState();
}

class _ImportUserFiguresScreenState extends State<ImportUserFiguresScreen> {
  late final Set<String> _add = {
    for (final item in widget.items)
      if (item.kind == UserFigureImportKind.add ||
          item.kind == UserFigureImportKind.copy)
        item.incoming.id,
  };
  final Set<String> _useTheirs = {};

  List<UserFigureImportItem> _of(UserFigureImportKind kind) => [
    for (final item in widget.items)
      if (item.kind == kind) item,
  ];

  int get _count => _add.length + _useTheirs.length;

  void _skip() => Navigator.of(context).pop(const UserFigureImportChoices());

  void _confirm() => Navigator.of(
    context,
  ).pop(UserFigureImportChoices(add: {..._add}, useTheirs: {..._useTheirs}));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final added = _of(UserFigureImportKind.add);
    final differs = _of(UserFigureImportKind.differs);
    final copies = _of(UserFigureImportKind.copy);
    final same = _of(UserFigureImportKind.same);

    Widget note(UserGlossaryEntry figure, {String? extra}) {
      final lines = [
        figure.definition,
        ?extra,
        if (widget.nameTaken.contains(figure.id))
          l10n.importUserFiguresNameTaken,
      ];
      return Text(lines.join('\n'));
    }

    Widget addTile(UserFigureImportItem item, {String? extra}) {
      final id = item.incoming.id;
      return CheckboxListTile(
        key: ValueKey('user-figure-import-add-$id'),
        value: _add.contains(id),
        onChanged: (value) =>
            setState(() => value == true ? _add.add(id) : _add.remove(id)),
        title: Text(item.incoming.name),
        subtitle: note(item.incoming, extra: extra),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.importUserFiguresTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.importUserFiguresIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (added.isNotEmpty) ...[
            _SectionHeader(l10n.importUserFiguresNewHeader),
            for (final item in added) addTile(item),
          ],
          if (differs.isNotEmpty) ...[
            _SectionHeader(l10n.importUserFiguresDiffersHeader),
            for (final item in differs)
              Column(
                key: ValueKey('user-figure-import-differs-${item.incoming.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: Text(item.incoming.name),
                    subtitle: note(item.incoming),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    // Named, so a screen reader says whose choice this is.
                    child: Semantics(
                      container: true,
                      label: item.incoming.name,
                      child: SegmentedButton<bool>(
                        key: ValueKey(
                          'user-figure-import-choice-${item.incoming.id}',
                        ),
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(l10n.importUserFiguresKeepMine),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(l10n.importUserFiguresUseTheirs),
                          ),
                        ],
                        selected: {_useTheirs.contains(item.incoming.id)},
                        onSelectionChanged: (selection) => setState(
                          () => selection.first
                              ? _useTheirs.add(item.incoming.id)
                              : _useTheirs.remove(item.incoming.id),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
          if (copies.isNotEmpty) ...[
            _SectionHeader(l10n.importUserFiguresCopyHeader),
            for (final item in copies)
              addTile(item, extra: l10n.importUserFiguresCopyNote),
          ],
          if (same.isNotEmpty) ...[
            _SectionHeader(l10n.importUserFiguresSameHeader),
            for (final item in same)
              ListTile(
                key: ValueKey('user-figure-import-same-${item.incoming.id}'),
                leading: const Icon(Icons.check),
                title: Text(item.incoming.name),
                textColor: theme.colorScheme.onSurfaceVariant,
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                key: const ValueKey('user-figure-import-skip'),
                onPressed: _skip,
                child: Text(l10n.importUserFiguresSkip),
              ),
              FilledButton(
                key: const ValueKey('user-figure-import-confirm'),
                onPressed: _confirm,
                child: Text(l10n.importUserFiguresConfirm(_count)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
