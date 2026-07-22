// Part of the Settings screen, split by section (issue #458: Diagnostics).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

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
          const SnackBar(content: Text('No diagnostics to export.')),
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
            const SnackBar(
              content: Text(
                "Couldn't prepare a safe (scrubbed) export, so nothing was "
                'saved. Please try again, or use full detail deliberately.',
              ),
            ),
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
            delivered ? 'Diagnostics log exported.' : 'Export cancelled.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't export the diagnostics log.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear diagnostics log?'),
        content: const Text(
          'This permanently deletes the local crash log from this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('diagnostics-clear-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
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
        const SnackBar(content: Text('Diagnostics log cleared.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        SectionHeader(title: 'Diagnostics'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            'When something goes wrong, the app records a technical note to a '
            'local log on this device to help diagnose the problem. It is '
            'never sent anywhere — there is no telemetry. You can export it to '
            'attach to a bug report, or clear it at any time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SectionHeader(title: 'Recent entries'),
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
                title: const Text("Couldn't read the diagnostics log"),
                subtitle: const Text(
                  'The local log may be inaccessible on this device. You can '
                  'still try to export or clear it.',
                ),
              );
            }
            final records = snapshot.data ?? const <CrashLogRecord>[];
            if (records.isEmpty) {
              return ListTile(
                key: const ValueKey('diagnostics-empty'),
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('No errors recorded'),
                subtitle: const Text(
                  'Nothing has been captured on this device.',
                ),
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
        SectionHeader(title: 'Export'),
        SwitchListTile(
          key: const ValueKey('diagnostics-full-detail-toggle'),
          secondary: const Icon(Icons.visibility_outlined),
          title: const Text('Include full detail (may contain your content)'),
          subtitle: const Text(
            'Off by default. When off, the export removes your content, file '
            'paths, emails, and phone numbers.',
          ),
          value: _includeFullDetail,
          onChanged: _busy
              ? null
              : (value) => setState(() => _includeFullDetail = value),
        ),
        ListTile(
          key: const ValueKey('diagnostics-export'),
          leading: const Icon(Icons.ios_share),
          title: const Text('Export / share log'),
          subtitle: Text(
            _includeFullDetail
                ? 'Shares the full, unredacted log.'
                : 'Shares a scrubbed copy safe to attach to a bug report.',
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
            'Clear log',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text('Delete the local crash log from this device.'),
          onTap: _busy ? null : _clear,
        ),
      ],
    );
  }
}
