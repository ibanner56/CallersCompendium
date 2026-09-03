import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/dance_reimport.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../diagnostics/error_log.dart';
import '../search/dance_detail_data.dart';
import 'dance_detail_screen.dart';

enum _ReimportSource { callersBox, contraDb, json }

/// Source selection and explicit online-row selection shared by the routed and
/// split-pane owners. It only returns an in-memory dance; owners decide where
/// the preview lives and when to commit it.
Future<DanceDetailData?> selectReimportDance(
  BuildContext context, {
  required Dance target,
  required CompendiumRepositories repos,
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
            (_ReimportSource.callersBox, OnlineSource.callersBox.label),
            (_ReimportSource.contraDb, OnlineSource.contraDb.label),
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

/// Owns the routed re-import flow shared by saved-detail owners.
///
/// The owner supplies the repositories and online services so route callers
/// retain control of their data lifecycle and tests can inject deterministic
/// seams. Collection's wide split pane intentionally keeps its embedded preview
/// implementation; this coordinator is for owners that push a standard preview
/// route.
class DanceReimportCoordinator {
  const DanceReimportCoordinator({
    required this.repos,
    required this.callersBox,
    required this.contraDb,
    this.picker = pickImportFile,
  });

  final CompendiumRepositories repos;
  final OnlineSearchService callersBox;
  final OnlineSearchService contraDb;
  final ImportPicker picker;

  Future<void> open(BuildContext context, DanceDetailData target) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final preview = await selectReimportDance(
        context,
        target: target.dance,
        repos: repos,
        callersBox: callersBox,
        contraDb: contraDb,
        picker: picker,
      );
      if (!context.mounted || preview == null) return;

      var importing = false;
      final committed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (previewContext) => DanceDetailScreen.preview(
            data: preview,
            onImport: () async {
              if (importing) return;
              importing = true;
              try {
                final result = await replaceDanceChoreography(
                  repos,
                  targetDanceId: target.dance.id,
                  incoming: preview.dance,
                  expectedUpdatedAt: target.dance.updatedAt,
                );
                if (!previewContext.mounted) return;
                if (result == DanceReimportResult.replaced) {
                  Navigator.of(previewContext).pop(true);
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        result == DanceReimportResult.targetMissing
                            ? AppLocalizations.of(
                                context,
                              ).danceReimportTargetMissing
                            : AppLocalizations.of(
                                context,
                              ).danceReimportTargetChanged,
                      ),
                    ),
                  );
                }
              } catch (error, stackTrace) {
                logCaughtErrorTypeOnly(
                  error,
                  stackTrace,
                  source: 'dance_reimport_flow.DanceReimportCoordinator.open',
                );
                if (previewContext.mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context).danceReimportSourceFailed,
                      ),
                    ),
                  );
                }
              } finally {
                importing = false;
              }
            },
          ),
        ),
      );
      if (context.mounted && committed == true) {
        messenger.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).danceReimported)),
        );
      }
    } on DanceReimportJsonException catch (error) {
      logCaughtErrorTypeOnly(
        error,
        StackTrace.current,
        source: 'dance_reimport_flow.DanceReimportCoordinator.open',
      );
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              error.programBearing
                  ? AppLocalizations.of(context).danceReimportProgramArchive
                  : AppLocalizations.of(context).danceReimportInvalidJson,
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'dance_reimport_flow.DanceReimportCoordinator.open',
      );
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).danceReimportSourceFailed,
            ),
          ),
        );
      }
    }
  }
}
