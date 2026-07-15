import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
Future<void> launchExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = tryParseHttpUrl(url);

  void reportFailure() {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't open link")),
    );
  }

  if (uri == null) {
    reportFailure();
    return;
  }

  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) reportFailure();
  } on PlatformException {
    reportFailure();
  } on Exception {
    reportFailure();
  }
}
