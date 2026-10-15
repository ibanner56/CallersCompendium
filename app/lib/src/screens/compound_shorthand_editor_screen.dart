import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../editor/figure_draft.dart';
import '../glossary/custom_figures.dart';
import '../widgets/compound_argument_editor.dart';

/// Creates or edits one compound shorthand (#709): a token that stands for one
/// of the user's own compound figures with the values chosen here. Pops the
/// edited [CompoundShorthand], or nothing when cancelled.
///
/// Only compounds this build can expand are offered. Each argument is chosen
/// within what the compound accepts, as on a dance-editor row.
class CompoundShorthandEditorScreen extends StatefulWidget {
  const CompoundShorthandEditorScreen({
    super.key,
    this.initial,
    this.existingTokens = const {},
  });

  /// The shorthand being edited, or null for a new one.
  final CompoundShorthand? initial;

  /// The normalized tokens of every other shorthand, of either kind.
  final Set<String> existingTokens;

  @override
  State<CompoundShorthandEditorScreen> createState() =>
      _CompoundShorthandEditorScreenState();
}

class _CompoundShorthandEditorScreenState
    extends State<CompoundShorthandEditorScreen> {
  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  late final TextEditingController _token = TextEditingController(
    text: widget.initial?.token ?? '',
  );
  StreamSubscription<List<UserGlossaryEntry>>? _sub;
  CompendiumRepositories? _repos;

  /// The compounds that can be expanded, by entry id, in name order.
  Map<String, ({UserGlossaryEntry entry, CompoundDefinition definition})>?
  _compounds;

  late String? _compoundId = widget.initial?.compoundId;
  late final Map<String, Object?> _args = {...?widget.initial?.args};
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_sub?.cancel());
    _sub = repos?.userGlossary.watchAll().listen((entries) {
      if (!mounted) return;
      final usable =
          [
            for (final entry in entries)
              if (entry.kind == UserGlossaryEntryKind.compound)
                if (decodeCompoundDefinition(entry.payload, contraTaxonomy)
                    case final definition?)
                  (entry: entry, definition: definition),
          ]..sort(
            (a, b) => a.entry.name.toLowerCase().compareTo(
              b.entry.name.toLowerCase(),
            ),
          );
      setState(() => _compounds = {for (final c in usable) c.entry.id: c});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _token.dispose();
    super.dispose();
  }

  void _pick(String? id) {
    final picked = id == null ? null : _compounds?[id];
    setState(() {
      _compoundId = id;
      _args
        ..clear()
        ..addAll(
          picked == null
              ? const {}
              : previewArguments(picked.definition, contraTaxonomy) ?? const {},
        );
      _error = null;
    });
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final token = _token.text.trim();
    String? error;
    final picked = _compoundId == null ? null : _compounds?[_compoundId];
    if (token.isEmpty) {
      error = l10n.shorthandEditorErrorEmpty;
    } else if (token.length > maxShorthandTokenLength) {
      error = l10n.shorthandEditorErrorTooLong(maxShorthandTokenLength);
    } else if (widget.existingTokens.contains(normalizeShorthandToken(token))) {
      error = l10n.shorthandEditorErrorDuplicate(token);
    } else if (picked == null) {
      error = l10n.compoundShorthandEditorNoFigure;
    } else if (expandCompound(picked.definition, _args, contraTaxonomy) ==
        null) {
      error = l10n.compoundShorthandEditorInvalidValues;
    }
    final shorthand = picked == null
        ? null
        : CompoundShorthand(
            token: token,
            compoundId: picked.entry.id,
            compoundName: picked.entry.name,
            args: {
              for (final p in picked.definition.params)
                if (_args[p.key] case final Object value) p.key: value,
            },
          );
    // What is saved must survive the next load: a text value over the stored
    // bound would drop the whole shorthand then.
    if (error == null && !CompoundShorthands.keeps(shorthand!)) {
      error = l10n.compoundEditorTooLong;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(shorthand);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final compounds = _compounds;
    final picked = _compoundId == null ? null : compounds?[_compoundId];
    final expanded = picked == null
        ? null
        : expandPlaceholder(
            CompoundPlaceholder(id: picked.entry.id, name: '', args: _args),
            (id) => compounds?[id]?.definition,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null
              ? l10n.shorthandEditorTitleNew
              : l10n.shorthandEditorTitleEdit,
        ),
        actions: [
          TextButton(
            key: const ValueKey('compound-shorthand-save'),
            onPressed: compounds == null ? null : _save,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                key: const ValueKey('compound-shorthand-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          TextField(
            key: const ValueKey('compound-shorthand-token'),
            controller: _token,
            maxLength: maxShorthandTokenLength,
            autofocus: widget.initial == null,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: l10n.shorthandEditorTokenLabel,
              helperText: l10n.shorthandEditorTokenHelper,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (compounds != null && compounds.isEmpty)
            Text(
              l10n.compoundShorthandEditorNoCompounds,
              key: const ValueKey('compound-shorthand-none'),
            )
          else if (compounds != null) ...[
            DropdownButtonFormField<String>(
              key: const ValueKey('compound-shorthand-compound'),
              initialValue: picked?.entry.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.compoundShorthandEditorFigureLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in compounds.values)
                  DropdownMenuItem(
                    value: c.entry.id,
                    child: Text(
                      _renderer.renderFreeText(c.entry.name, dialect),
                    ),
                  ),
              ],
              onChanged: _pick,
            ),
            if (picked != null) ...[
              for (final param in picked.definition.params)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: CompoundArgumentEditor(
                    keyPrefix: 'compound-shorthand-arg',
                    definition: picked.definition,
                    param: param,
                    value: _args[param.key],
                    dialect: dialect,
                    onChanged: (value) => setState(() {
                      _args[param.key] = value;
                      _error = null;
                    }),
                  ),
                ),
              if (expanded != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.danceEditorCompoundExpandsTo(
                      expanded.length,
                      CompoundDefinition.beatsOf(expanded, contraTaxonomy),
                    ),
                    key: const ValueKey('compound-shorthand-expands'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
