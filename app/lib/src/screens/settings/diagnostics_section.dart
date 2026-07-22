// Part of the Settings screen, split by section (issue #458: Diagnostics).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/crash_log_io.dart';
import '../../diagnostics/crash_log_store.dart';
import '../../diagnostics/sensitive_terms.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';

/// Gathers the user-content terms the scrubbed export must redact. Defaults to
/// [collectSensitiveTerms] over the ambient repositories; injectable in tests.
typedef SensitiveTermsProvider = Future<Set<String>> Function();

/// Settings ▸ Diagnostics (issue #458).
///
/// Surfaces the **local, offline** crash log: the most recent captured errors,
/// an Export/Share action, and Clear. Export defaults to a **scrubbed** variant
/// (contact info + user content removed); a clearly-labelled "Include full
/// detail" toggle produces the raw variant for local troubleshooting. Nothing
/// here is ever transmitted — export always goes through the OS save/share
/// flow the user explicitly invokes.
class DiagnosticsSection extends StatefulWidget {
  const DiagnosticsSection({
    super.key,
    this.store,
    this.logSaver,
    this.sensitiveTermsProvider,
  });

  /// The crash-log store to read/clear/export. Defaults to the app-support
  /// store used by the running app; injected in tests against a temp dir.
  final CrashLogStore? store;

  /// Test seam for delivering the exported log; defaults to
  /// [saveDiagnosticsLog].
  final LogSaver? logSaver;

  /// Test seam for the redaction term source; defaults to
  /// [collectSensitiveTerms] over the ambient repositories.
  final SensitiveTermsProvider? sensitiveTermsProvider;

  /// How many recent entries the in-app list shows.
  static const int viewLimit = 50;

  @override
  State<DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends State<DiagnosticsSection> {
  late final CrashLogStore _store;
  late Future<List<CrashLogRecord>> _recordsFuture;
  bool _includeFullDetail = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Reuse the app-wide store (the same instance the global crash reporter in
    // main.dart appends to): CrashLogStore.appSupport() returns a shared
    // singleton, so reads/exports/clears here serialize against those writes
    // through one queue instead of racing a second store over the same files.
    _store = widget.store ?? CrashLogStore.appSupport();
    _recordsFuture = _store.readRecords(limit: DiagnosticsSection.viewLimit);
  }

  void _reload() {
    // The clear/export flows are async; the user may have navigated away by the
    // time they finish, so never call setState on a disposed State.
    if (!mounted) return;
    setState(() {
      _recordsFuture = _store.readRecords(limit: DiagnosticsSection.viewLimit);
    });
  }

  // The exported log is an exported-document *body*, not on-screen UI. Like the
  // PDF/text export builders it stays English pending the product decision on
  // whether exports follow the UI language (see docs/dev/localization.md
  // "permanent exceptions"), so these lines are intentionally not localized.
  String _buildExportText(List<CrashLogRecord> records, {required bool full}) {
    final buffer = StringBuffer()
      ..writeln("Caller's Compendium — diagnostics log")
      ..writeln('Exported (UTC): ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln(
        full
            ? 'Mode: FULL DETAIL — may contain your content and file paths'
            : 'Mode: scrubbed — user content, file paths, emails, and phone '
                  'numbers removed',
      )
      ..writeln('Records: ${records.length}')
      ..writeln('=' * 60);
    for (final record in records) {
      buffer
        ..writeln(record.toReadable())
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // Resolve the redaction-term source synchronously (before any await) so we
    // never touch `context` across an async gap.
    final provider = widget.sensitiveTermsProvider;
    final repositories = provider == null
        ? RepositoriesScope.of(context)
        : null;
    try {
      final records = await _store.readRecords(newestFirst: false);
      if (records.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.diagnosticsNoDiagnosticsToExport)),
        );
        return;
      }
      final full = _includeFullDetail;
      final List<CrashLogRecord> forExport;
      if (full) {
        forExport = records;
      } else {
        final Set<String> terms;
        try {
          terms = provider != null
              ? await provider()
              : await collectSensitiveTerms(repositories!);
        } catch (_) {
          // Fail-closed (OWASP): if we can't gather the terms to redact, do NOT
          // fall back to writing a file labelled "scrubbed" that could still
          // contain user content. Abort with a clear message instead.
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.diagnosticsScrubbedExportUnavailable)),
          );
          return;
        }
        final redactor = CrashRedactor(userContentTerms: terms);
        forExport = [for (final r in records) r.scrubbed(redactor)];
      }
      final text = _buildExportText(forExport, full: full);
      final saver = widget.logSaver ?? saveDiagnosticsLog;
      final delivered = await saver(text, diagnosticsLogFileName());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            delivered
                ? l10n.diagnosticsLogExported
                : l10n.diagnosticsExportCancelled,
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.diagnosticsExportFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.diagnosticsClearLogTitle),
        content: Text(l10n.diagnosticsClearLogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('diagnostics-clear-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.diagnosticsClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _store.clear();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.diagnosticsLogCleared)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        SectionHeader(title: l10n.diagnosticsHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            l10n.diagnosticsIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SectionHeader(title: l10n.diagnosticsRecentEntriesHeader),
        FutureBuilder<List<CrashLogRecord>>(
          future: _recordsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            // Check for a read failure BEFORE the empty state: on error
            // snapshot.data is null, and treating that as "no records" would
            // render the reassuring "No errors recorded" tile while actually
            // hiding a log we couldn't read. Surface the failure instead.
            if (snapshot.hasError) {
              return ListTile(
                key: const ValueKey('diagnostics-error'),
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(l10n.diagnosticsReadFailedTitle),
                subtitle: Text(l10n.diagnosticsReadFailedSubtitle),
              );
            }
            final records = snapshot.data ?? const <CrashLogRecord>[];
            if (records.isEmpty) {
              return ListTile(
                key: const ValueKey('diagnostics-empty'),
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l10n.diagnosticsEmptyTitle),
                subtitle: Text(l10n.diagnosticsEmptySubtitle),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < records.length; i++)
                  ListTile(
                    key: ValueKey('diagnostics-entry-$i'),
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(
                      records[i].summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${records[i].timestampUtc.toIso8601String()} · '
                      '${records[i].source}',
                    ),
                    isThreeLine: false,
                  ),
              ],
            );
          },
        ),
        SectionHeader(title: l10n.diagnosticsExportHeader),
        SwitchListTile(
          key: const ValueKey('diagnostics-full-detail-toggle'),
          secondary: const Icon(Icons.visibility_outlined),
          title: Text(l10n.diagnosticsFullDetailTitle),
          subtitle: Text(l10n.diagnosticsFullDetailSubtitle),
          value: _includeFullDetail,
          onChanged: _busy
              ? null
              : (value) => setState(() => _includeFullDetail = value),
        ),
        ListTile(
          key: const ValueKey('diagnostics-export'),
          leading: const Icon(Icons.ios_share),
          title: Text(l10n.diagnosticsExportShareLogTitle),
          subtitle: Text(
            _includeFullDetail
                ? l10n.diagnosticsExportShareFullSubtitle
                : l10n.diagnosticsExportShareScrubbedSubtitle,
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _busy ? null : _export,
        ),
        ListTile(
          key: const ValueKey('diagnostics-clear'),
          leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          title: Text(
            l10n.diagnosticsClearLogRowTitle,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: Text(l10n.diagnosticsClearLogRowSubtitle),
          onTap: _busy ? null : _clear,
        ),
      ],
    );
  }
}
