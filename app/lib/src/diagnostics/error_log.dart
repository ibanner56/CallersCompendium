/// Process-wide seam so any caught, user-facing error can reach the crash log
/// (issue #963) without a [BuildContext].
///
/// The prior state: [CrashLogSink] was reachable only from `main.dart`, which
/// held the single [CrashReporter] instance as a local variable threaded
/// through one widget field (`CompendiumApp.crashReporter`). A screen that
/// catches an error and shows a snackbar had no path to the log at all — not
/// even via an [InheritedWidget] scope, because roughly fifty of the sites
/// that need this run after an `await` (scope lookups need a [BuildContext]
/// captured *before* the gap) or in dialog/service code with no context in
/// scope in the first place. One reported site (`main.dart`'s
/// `_handleIncomingUrl`) sits *above* `RepositoriesScope` in the tree, so an
/// `InheritedWidget`-based fix would have missed the exact case the issue is
/// about.
///
/// This mirrors the existing process-wide singleton pattern already used for
/// the store itself ([CrashLogStore.appSupport]): a static slot, installed
/// once from `main()`, read from everywhere. [installCaughtErrorLog] is called
/// right next to [installGlobalErrorHandlers] so both halves of "capture every
/// application error" are installed together.
///
/// [logCaughtError] is a deliberate no-op until installed, so the ~60 widget
/// tests that pump screens without calling [installCaughtErrorLog] are
/// unaffected — none of them need to construct or inject a sink.
library;

import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';

CrashLogSink? _sink;

/// Installs [sink] as the process-wide destination for [logCaughtError].
/// Call once, from `main()`, alongside [installGlobalErrorHandlers].
void installCaughtErrorLog(CrashLogSink sink) {
  _sink = sink;
}

/// Test-only: clears the installed sink so tests don't leak state into each
/// other (mirrors the reset a fresh `main()` run would have).
@visibleForTesting
void resetCaughtErrorLogForTesting() {
  _sink = null;
}

/// Records a caught error that was (or is about to be) surfaced to the user —
/// a snackbar, an inline error banner, an alert dialog — so it appears in the
/// on-device diagnostic log alongside uncaught crashes (issue #963).
///
/// A no-op until [installCaughtErrorLog] has run (e.g. in a widget test that
/// never installs a sink), and internally exception-proof: this call sits
/// *inside* a UI catch block, ahead of the error surface the user is about to
/// see, so a failure here must never prevent that surface from showing. Any
/// failure in this function is therefore swallowed, mirroring
/// [CrashReporter]'s own internal guard rather than adding a second one on top
/// of it — a throw here would simply be caught here, not propagated to
/// [CrashReporter] to catch again.
///
/// [source] should identify the call site as `<file-stem>.<method>`, e.g.
/// `dance_list_screen._importOnline`, so the log reads like a stack of its
/// own even though it has no single global handler name to fall back on.
void logCaughtError(Object error, StackTrace? stack, {required String source}) {
  final sink = _sink;
  if (sink == null) return;
  try {
    sink.record(error, stack, source: source);
  } catch (_) {
    // diagnostics: silent — this IS the logging sink; it cannot log its own
    // failure without risking infinite recursion or masking the real error
    // surface this call sits ahead of (see the doc comment above).
  }
}

/// Records that an error of [error]'s runtime type was caught at [source],
/// without persisting [error]'s own message or the caught object itself.
///
/// Some catch sites already treat their caught error as unsafe to surface
/// verbatim — e.g. a raw network/parse failure that could echo response body
/// content or a raw path (CWE-209) — and only ever show the user a curated,
/// localized message built from a *typed* discriminator (see
/// `UrlFetchException`'s own doc for the model this follows). Those sites use
/// this instead of [logCaughtError] so the diagnostic log gains "something of
/// this shape failed here" without becoming a second, less-scrutinized export
/// path for the same content [logCaughtError] would otherwise leak.
void logCaughtErrorTypeOnly(
  Object error,
  StackTrace? stack, {
  required String source,
}) {
  logCaughtError(_TypeOnlyError(error.runtimeType), stack, source: source);
}

/// A stand-in [Exception] whose `toString()` reveals only the original
/// error's runtime type, for [logCaughtErrorTypeOnly]. Its own runtime type
/// (`_TypeOnlyError`) is deliberately visible in the persisted record's
/// `errorType` field too — a reader must be able to tell "this record's detail
/// was intentionally withheld" from "this record's error genuinely was
/// `_TypeOnlyError`", and the message says which is true.
class _TypeOnlyError implements Exception {
  const _TypeOnlyError(this.originalType);

  final Type originalType;

  @override
  String toString() =>
      'redacted per source policy — original type was $originalType';
}
