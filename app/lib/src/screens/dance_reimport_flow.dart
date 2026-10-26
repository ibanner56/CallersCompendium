import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/dance_reimport.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../diagnostics/error_log.dart';
import '../search/dance_detail_data.dart';
import 'dance_detail_screen.dart';

enum _ReimportSource { callersBox, contraDb, link, json }

/// Source selection and explicit online-row selection shared by the routed and
/// split-pane owners. An online dance is found either by searching the source
/// for the saved title, or from a Caller's Box or ContraDB link or id the user
/// pastes. It only returns an in-memory dance; owners decide where the preview
/// lives and when to commit it.
///
/// Throws a [UrlFetchException] already attributed to the source that failed
/// (`attributeFetchFailure`), a [DanceReimportFiguresUnavailableException]
/// when the source withheld the dance's figures, or a
/// [DanceReimportJsonException] for an unusable file. Owners map each to a
/// message; anything else is an unexpected failure.
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
            (_ReimportSource.link, l10n.danceReimportLinkOrId),
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

  OnlineSearchService serviceFor(OnlineSource online) =>
      online == OnlineSource.callersBox ? callersBox : contraDb;

  final OnlineSearchResultRow selected;
  if (source == _ReimportSource.link) {
    final link = await showDialog<_ReimportLink>(
      context: context,
      builder: (context) => _ReimportLinkDialog(
        initialSource: _onlineSourceOf(target.provenance?.source),
      ),
    );
    if (link == null || !context.mounted) return null;
    // The shape an OS-shared link uses (`main.dart`): the service rebuilds its
    // own canonical fetch URL from the validated id.
    selected = OnlineSearchResultRow(
      source: link.source,
      id: link.id,
      name: '',
      author: '',
      formation: '',
    );
  } else {
    final online = source == _ReimportSource.callersBox
        ? OnlineSource.callersBox
        : OnlineSource.contraDb;
    final results = await _attributed(
      online,
      () => serviceFor(online).search(OnlineSearchQuery(title: target.title)),
    );
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
    final chosen = await showDialog<OnlineSearchResultRow>(
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
    if (chosen == null || !context.mounted) return null;
    selected = chosen;
  }
  final preview = await _attributed(
    selected.source,
    () => serviceFor(selected.source).loadPreview(repos, selected),
  );
  rejectFigurelessReimport(preview.plan);
  return preview.detail;
}

/// Runs [request] against [source], re-labelling a generic fetch failure (a
/// bare HTTP status, unreachable, timeout) as that source's own, so a missing
/// Caller's Box id reads "no dance with that id" rather than a status code
/// (#1497).
Future<T> _attributed<T>(
  OnlineSource source,
  Future<T> Function() request,
) async {
  try {
    return await request();
  } on UrlFetchException catch (error, stackTrace) {
    // diagnostics: silent — rethrown, relabelled; every owner of
    // selectReimportDance logs it where it is shown.
    Error.throwWithStackTrace(
      attributeFetchFailure(error, switch (source) {
        OnlineSource.callersBox => ImportSourceKind.callersBox,
        OnlineSource.contraDb => ImportSourceKind.contraDb,
      }),
      stackTrace,
    );
  }
}

/// The online source a dance was imported from, or null when it has none or
/// came from somewhere a link cannot name (a file, a manual entry).
OnlineSource? _onlineSourceOf(ProvenanceSource? source) => switch (source) {
  ProvenanceSource.callersbox => OnlineSource.callersBox,
  ProvenanceSource.contradb => OnlineSource.contraDb,
  _ => null,
};

/// What [_ReimportLinkDialog] returns: a validated dance id and its source.
typedef _ReimportLink = ({OnlineSource source, String id});

/// Asks for a Caller's Box or ContraDB dance link or id. A recognised pasted
/// link always selects its own source; the selector only decides where a bare
/// id is looked up, and it starts on [initialSource] -- the target dance's own
/// source -- so an id copied from that source is not fetched from the other.
/// Input the URL builders reject is reported here, inline, so it can be fixed
/// without starting over; nothing is fetched until it is valid.
class _ReimportLinkDialog extends StatefulWidget {
  const _ReimportLinkDialog({this.initialSource});

  /// Null starts on The Caller's Box.
  final OnlineSource? initialSource;

  @override
  State<_ReimportLinkDialog> createState() => _ReimportLinkDialogState();
}

class _ReimportLinkDialogState extends State<_ReimportLinkDialog> {
  final _controller = TextEditingController();
  late var _source = widget.initialSource ?? OnlineSource.callersBox;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Unlike the Import screen, a manual choice does not pin the source: here
    // it only matters for a bare id, and a link names its own source.
    final detected = switch (detectSourceForUrl(
      value,
      defaultImportSources(),
    )?.kind) {
      ImportSourceKind.callersBox => OnlineSource.callersBox,
      ImportSourceKind.contraDb => OnlineSource.contraDb,
      _ => null,
    };
    setState(() {
      if (detected != null) _source = detected;
      _error = null;
    });
  }

  void _submit() {
    final input = _controller.text;
    try {
      final id = switch (_source) {
        OnlineSource.callersBox => callersBoxDanceIdFromInput(input),
        OnlineSource.contraDb => contraDbDanceIdFromInput(input),
      };
      Navigator.pop<_ReimportLink>(context, (source: _source, id: id));
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_reimport_flow._ReimportLinkDialog._submit',
      );
      setState(
        () => _error = importErrorMessage(AppLocalizations.of(context), error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.danceReimportLinkOrId),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<OnlineSource>(
              key: const ValueKey('reimport-link-source'),
              segments: [
                for (final online in OnlineSource.values)
                  ButtonSegment(
                    value: online,
                    label: Text(
                      online.label,
                      key: ValueKey('reimport-link-source-${online.name}'),
                    ),
                  ),
              ],
              selected: {_source},
              onSelectionChanged: (selection) => setState(() {
                _source = selection.single;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('reimport-link-field'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.importReviewUrlLabel,
                hintText: l10n.importReviewUrlHint,
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('reimport-link-fetch'),
          onPressed: _submit,
          child: Text(l10n.importReviewFetch),
        ),
      ],
    );
  }
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
    } on UrlFetchException catch (error, stackTrace) {
      // Log-safe by construction: a typed reason plus status/timeout numbers.
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_reimport_flow.DanceReimportCoordinator.open',
      );
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              importErrorMessage(AppLocalizations.of(context), error),
            ),
          ),
        );
      }
    } on DanceReimportFiguresUnavailableException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_reimport_flow.DanceReimportCoordinator.open',
      );
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).danceReimportFiguresUnavailable,
            ),
          ),
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
