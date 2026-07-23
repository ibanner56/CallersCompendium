import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// The friendly, recoverable widget shown in place of a subtree that failed to
/// build, replacing Flutter's raw red error box (issue #458).
///
/// It is intentionally self-contained — it provides its own [Directionality]
/// and [Material] so it renders correctly even when the failure happens above
/// the app's own theme/localization scopes — and offers a "Copy details" hook
/// so a tester can grab the error text. The same error is already captured to
/// the local crash log via `FlutterError.onError`, so this widget only needs to
/// surface it; it deliberately does no I/O of its own to avoid a
/// crash-during-crash loop.
class CrashFallback extends StatefulWidget {
  const CrashFallback({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  State<CrashFallback> createState() => _CrashFallbackState();
}

class _CrashFallbackState extends State<CrashFallback> {
  bool _copied = false;

  String get _detailsText {
    final stack = widget.details.stack;
    final buffer = StringBuffer(widget.details.exceptionAsString());
    if (stack != null) buffer.write('\n\n$stack');
    return buffer.toString();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _detailsText));
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      // Copying is best-effort; never let it throw out of the fallback.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n =
        Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        lookupAppLocalizations(const Locale('en'));
    // Honour the ambient text direction so localized copy renders correctly in
    // RTL locales; fall back to LTR only when this card is shown without a
    // Directionality ancestor (e.g. a very early root-level crash).
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return Directionality(
      textDirection: textDirection,
      child: Material(
        color: const Color(0xFFF7F2EC),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                key: const ValueKey('crash-fallback'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sentiment_dissatisfied_outlined,
                    size: 48,
                    color: Color(0xFF6B4F3A),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.crashFallbackTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3A2E22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.crashFallbackBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF5A4A3A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    key: const ValueKey('crash-fallback-copy'),
                    onPressed: _copied ? null : _copy,
                    icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                    label: Text(
                      _copied
                          ? l10n.crashFallbackCopied
                          : l10n.crashFallbackCopyDetails,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
