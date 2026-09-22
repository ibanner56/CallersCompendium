// The Device Sync pairing flow (spec §6.2, §6.14 items 1, 2, 3, 5, 6).
import 'package:compendium_core/compendium_core.dart'
    show SyncId, generateSyncId;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/backup_io.dart';
import '../../data/backup_service.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_http_client.dart';
import '../../sync/sync_scope.dart';
import '../../theme/app_spacing.dart';

/// Whether the user is creating a new store or attaching to one that already
/// exists. The pairing surface must ask this explicitly and never infer it
/// from a network response (spec §6.14 item 5).
enum SyncPairingMode { create, connect }

/// Pushes the pairing flow and returns once it has either connected
/// (`sync_id` is persisted and the coordinator is being (re)built) or the user
/// backed out. The caller does not need the return value; it exists so a
/// caller that wants to know can await it.
Future<void> showSyncPairingScreen(
  BuildContext context, {
  BackupSaver? backupSaver,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SyncPairingScreen(backupSaver: backupSaver),
    ),
  );
}

class SyncPairingScreen extends StatefulWidget {
  const SyncPairingScreen({super.key, this.backupSaver});

  /// Test seam for the pairing backup offer; defaults to [saveBackupToFile].
  final BackupSaver? backupSaver;

  @override
  State<SyncPairingScreen> createState() => _SyncPairingScreenState();
}

class _SyncPairingScreenState extends State<SyncPairingScreen> {
  SyncPairingMode? _mode;
  late String _candidateId;
  final _connectController = TextEditingController();
  String? _fieldError;
  bool _backupOffered = false;
  bool _busy = false;
  SyncPairingProbe? _probe;

  @override
  void initState() {
    super.initState();
    _candidateId = generateSyncId().value;
  }

  @override
  void dispose() {
    _probe?.close?.call();
    _connectController.dispose();
    super.dispose();
  }

  void _chooseCreate() => setState(() => _mode = SyncPairingMode.create);

  void _chooseConnect() => setState(() => _mode = SyncPairingMode.connect);

  void _regenerate() => setState(() => _candidateId = generateSyncId().value);

  Future<void> _offerBackup(bool accept) async {
    if (accept) {
      final repos = RepositoriesScope.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final l10n = AppLocalizations.of(context);
      try {
        final service = BackupService(repos);
        final now = DateTime.now();
        final json = await service.exportToJson(createdAt: now);
        final saver = widget.backupSaver ?? saveBackupToFile;
        final delivered = await saver(
          json,
          'callers-compendium-backup-${now.toUtc().toIso8601String().substring(0, 10)}.json',
        );
        if (delivered) await service.recordBackup(now);
      } on Exception catch (e, st) {
        logCaughtError(e, st, source: 'sync_pairing_screen._offerBackup');
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.backupExportFailed)),
          );
        }
      }
    }
    if (mounted) setState(() => _backupOffered = true);
  }

  Future<void> _submit(SyncController controller) async {
    final l10n = AppLocalizations.of(context);
    final mode = _mode!;
    String candidate;
    if (mode == SyncPairingMode.create) {
      candidate = _candidateId;
    } else {
      final parsed = SyncId.tryParse(_connectController.text);
      if (parsed == null) {
        setState(() => _fieldError = l10n.settingsSyncPairingInvalidPhrase);
        return;
      }
      candidate = parsed.value;
    }

    final probe = controller.probeFor(candidate);
    if (probe == null) {
      setState(() => _fieldError = l10n.settingsSyncPairingUnreachable);
      return;
    }
    _probe = probe;
    setState(() {
      _busy = true;
      _fieldError = null;
    });
    // The busy spinner covers only the network probe and the persist step —
    // never the completion dialog's own wait for the user to dismiss it,
    // which would otherwise leave an indeterminate spinner running for as
    // long as that dialog is open.
    try {
      if (mode == SyncPairingMode.create) {
        final response = await probe.createStore();
        if (response.kind == SyncResponseKind.conflict) {
          setState(() => _fieldError = l10n.settingsSyncPairingAlreadyInUse);
          return;
        }
        if (!response.isSuccess) {
          setState(() => _fieldError = l10n.settingsSyncPairingUnreachable);
          return;
        }
      } else {
        // Connecting never infers creation from a missing store (spec §5.2,
        // §6.14 item 5): a 404 is reported and the request stops here.
        final result = await probe.getStore(previouslyUsed: false);
        if (result.isMissing) {
          setState(() => _fieldError = l10n.settingsSyncPairingNotFound);
          return;
        }
        if (!result.response.isSuccess) {
          setState(() => _fieldError = l10n.settingsSyncPairingUnreachable);
          return;
        }
      }

      await controller.completePairing(candidate);
    } finally {
      _probe?.close?.call();
      _probe = null;
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await _showCompletion(controller);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showCompletion(SyncController controller) async {
    final l10n = AppLocalizations.of(context);
    final duplicates = controller.lastResult?.duplicateCount ?? 0;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const ValueKey('sync-pairing-complete-dialog'),
        title: Text(l10n.settingsSyncPairingComplete),
        content: Text(
          duplicates > 0
              ? l10n.settingsSyncPairingCompleteDuplicates(duplicates)
              : l10n.settingsSyncPairingCompleteBody,
        ),
        actions: [
          TextButton(
            key: const ValueKey('sync-pairing-complete-ok'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = SyncScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSyncPairingTitle)),
      body: SafeArea(
        child: _mode == null
            ? _buildChoice(l10n)
            : _buildDetail(context, l10n, controller),
      ),
    );
  }

  Widget _buildChoice(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(
            l10n.settingsSyncPairingChooseHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Card(
          child: ListTile(
            key: const ValueKey('sync-pairing-create'),
            leading: const Icon(Icons.add_circle_outline),
            title: Text(l10n.settingsSyncPairingCreateTitle),
            subtitle: Text(l10n.settingsSyncPairingCreateSubtitle),
            onTap: _chooseCreate,
          ),
        ),
        Card(
          child: ListTile(
            key: const ValueKey('sync-pairing-connect'),
            leading: const Icon(Icons.link),
            title: Text(l10n.settingsSyncPairingConnectTitle),
            subtitle: Text(l10n.settingsSyncPairingConnectSubtitle),
            onTap: _chooseConnect,
          ),
        ),
      ],
    );
  }

  Widget _buildDetail(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
  ) {
    final theme = Theme.of(context);
    final create = _mode == SyncPairingMode.create;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (create) ...[
          Text(
            l10n.settingsSyncPairingYourPhrase,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            _candidateId,
            key: const ValueKey('sync-pairing-phrase'),
            style: theme.textTheme.headlineSmall,
          ),
          TextButton(
            key: const ValueKey('sync-pairing-regenerate'),
            onPressed: _busy ? null : _regenerate,
            child: Text(l10n.settingsSyncPairingRegenerate),
          ),
        ] else ...[
          TextField(
            key: const ValueKey('sync-pairing-phrase-field'),
            controller: _connectController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: l10n.settingsSyncPairingEnterPhrase,
              hintText: l10n.settingsSyncPairingEnterPhraseHint,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Disclosure(
          key: const ValueKey('sync-pairing-sharing-disclosure'),
          icon: Icons.group_outlined,
          title: l10n.settingsSyncPairingSharingTitle,
          body: l10n.settingsSyncPairingSharingBody,
        ),
        const SizedBox(height: AppSpacing.sm),
        _Disclosure(
          key: const ValueKey('sync-pairing-credential-disclosure'),
          icon: Icons.key_off_outlined,
          title: l10n.settingsSyncPairingCredentialTitle,
          body: l10n.settingsSyncPairingCredentialBody,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!_backupOffered)
          Card(
            key: const ValueKey('sync-pairing-backup-offer'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsSyncPairingBackupOfferTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(l10n.settingsSyncPairingBackupOfferBody),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      TextButton(
                        key: const ValueKey('sync-pairing-backup-skip'),
                        onPressed: () => _offerBackup(false),
                        child: Text(l10n.settingsSyncPairingBackupOfferSkip),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      FilledButton(
                        key: const ValueKey('sync-pairing-backup-accept'),
                        onPressed: () => _offerBackup(true),
                        child: Text(l10n.settingsSyncPairingBackupOfferAccept),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_fieldError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _fieldError!,
              key: const ValueKey('sync-pairing-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const ValueKey('sync-pairing-continue'),
          onPressed: _busy || !_backupOffered
              ? null
              : () => _submit(controller),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.settingsSyncPairingContinue),
        ),
      ],
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.secondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
