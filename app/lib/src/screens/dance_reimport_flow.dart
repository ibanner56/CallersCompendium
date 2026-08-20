import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/dance_reimport.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/repositories_scope.dart';
import '../search/dance_detail_data.dart';

enum _ReimportSource { callersBox, contraDb, json }

/// Source selection and explicit online-row selection shared by the routed and
/// split-pane owners. It only returns an in-memory dance; owners decide where
/// the preview lives and when to commit it.
Future<DanceDetailData?> selectReimportDance(
  BuildContext context, {
  required Dance target,
  required OnlineSearchService callersBox,
  required OnlineSearchService contraDb,
  ImportPicker picker = pickImportFile,
}) async {
  final l10n = AppLocalizations.of(context);
  final source = await showDialog<_ReimportSource>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.danceReimport),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in [
            (_ReimportSource.callersBox, "Caller's Box"),
            (_ReimportSource.contraDb, 'ContraDB'),
            (_ReimportSource.json, l10n.danceReimportJson),
          ])
            ListTile(
              key: ValueKey('reimport-source-${entry.$1.name}'),
              title: Text(entry.$2),
              onTap: () => Navigator.pop(context, entry.$1),
            ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final repos = RepositoriesScope.of(context);
  if (source == _ReimportSource.json) {
    final payload = await picker();
    if (payload == null) return null;
    final plan = await planSingleDanceJson(repos, payload);
    return reimportPreviewData(plan.draft.dance);
  }

  final service = source == _ReimportSource.callersBox ? callersBox : contraDb;
  final results = await service.search(OnlineSearchQuery(title: target.title));
  if (!context.mounted) return null;
  if (results.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.danceReimport),
        content: Text(l10n.danceReimportNoResults),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
    return null;
  }
  final selected = await showDialog<OnlineSearchResultRow>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.danceReimportChooseResult),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final result in results)
                ListTile(
                  key: ValueKey(
                    'reimport-result-${result.source.name}-${result.id}',
                  ),
                  title: Text(result.name),
                  subtitle: Text(
                    [
                      result.author,
                      result.formation,
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  onTap: () => Navigator.pop(context, result),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (selected == null || !context.mounted) return null;
  return (await service.loadPreview(repos, selected)).detail;
}
