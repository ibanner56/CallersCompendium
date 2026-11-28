import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../diagnostics/error_log.dart';

/// Parses [url] into a launchable `Uri`, returning `null` unless it is a
/// non-empty, well-formed **http/https** URL. Guards the UI so we never render
/// a launchable control (or attempt a launch) for a missing, malformed, or
/// non-web URL (e.g. `mailto:`, `javascript:`) — those fall back to plain text.
Uri? tryParseHttpUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (!uri.isScheme('http') && !uri.isScheme('https')) return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// Opens [url] in the user's browser / external app.
///
/// Validates [url] with [tryParseHttpUrl] and launches with
/// [LaunchMode.externalApplication]. Any failure — an invalid URL, a
/// `false` from [launchUrl], or a thrown [Exception]/[PlatformException] —
/// is swallowed and surfaced as a "Couldn't open link" [SnackBar] rather than
/// crashing. Callers should only expose a launchable control when
/// [tryParseHttpUrl] returns non-null, but this re-checks defensively.
Future<void> launchExternalUrl(BuildContext context, String url) =>
    _launch(context, tryParseHttpUrl(url), 'launchExternalUrl');

/// Opens a new email to [address] in the user's mail app (a `mailto:` link),
/// with the same failure handling as [launchExternalUrl]: a device with no
/// mail app, or a refused launch, shows "Couldn't open link". Callers show
/// [address] itself on the control, so it can still be copied by hand.
Future<void> launchEmail(BuildContext context, String address) {
  final trimmed = address.trim();
  final valid = RegExp(r'^[^@\s:/?#]+@[^@\s:/?#]+$').hasMatch(trimmed);
  return _launch(
    context,
    valid ? Uri(scheme: 'mailto', path: trimmed) : null,
    'launchEmail',
  );
}

Future<void> _launch(BuildContext context, Uri? uri, String caller) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  final source = 'launch_external_url.$caller';

  void reportFailure() {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.commonCouldntOpenLink)),
    );
  }

  if (uri == null) {
    reportFailure();
    return;
  }

  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) reportFailure();
  } on PlatformException catch (e, s) {
    // Type-only: a platform launch failure's message commonly embeds the
    // full attempted URL (e.g. Android's ACTIVITY_NOT_FOUND intent dump
    // includes the target `dat=<uri>`), and `CrashRedactor` deliberately
    // never scrubs http/https URLs (see its own doc) so the log's scrubbed
    // export could otherwise leak whatever URL/query string the user tapped
    // (issue #963's redaction concern — same treatment as the online-import
    // transport errors in `dance_list_screen.dart`/`import_review_screen.dart`).
    logCaughtErrorTypeOnly(e, s, source: source);
    reportFailure();
  } on Exception catch (e, s) {
    // Same URL-leak concern as the PlatformException branch above.
    logCaughtErrorTypeOnly(e, s, source: source);
    reportFailure();
  }
}
