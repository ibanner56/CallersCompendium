import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/diagnostics/crash_fallback.dart';

/// "Copy details" on the crash fallback produces the text a tester is invited
/// to paste into a bug report, so it follows the same rule as the scrubbed
/// diagnostics export (#1469): the error's type and a redacted stack, never
/// the error's message, which can carry user content (a dance title echoed in
/// a failed statement's parameters, say). Post-audit finding flows-7.
void main() {
  const sentinel = 'SENTINEL Lady of the Lake';

  Future<String?> copyFrom(
    WidgetTester tester,
    FlutterErrorDetails details,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(CrashFallback(details: details));
    await tester.tap(find.byKey(const ValueKey('crash-fallback-copy')));
    await tester.pumpAndSettle();
    return clipboardText;
  }

  testWidgets('copies the error type and a redacted stack, not the message', (
    tester,
  ) async {
    final stack = StackTrace.fromString(
      '#0      DanceRepository.save (file:///home/jane.doe/src/app/lib/repo.dart:12:3)\n'
      '#1      main (package:compendium_app/main.dart:4:1)\n',
    );
    final copied = await copyFrom(
      tester,
      FlutterErrorDetails(exception: StateError(sentinel), stack: stack),
    );

    expect(copied, isNotNull);
    expect(copied, contains('StateError'));
    expect(copied, isNot(contains('SENTINEL')));
    expect(copied, isNot(contains('Lady of the Lake')));
    // The stack is kept for the report, with the same redaction the scrubbed
    // export applies: an absolute path (here, a home directory name) is
    // collapsed, while an app frame survives.
    expect(copied, contains('DanceRepository.save'));
    expect(copied, contains('package:compendium_app/main.dart'));
    expect(copied, isNot(contains('jane.doe')));
  });

  testWidgets('copies the type alone when there is no stack', (tester) async {
    final copied = await copyFrom(
      tester,
      FlutterErrorDetails(exception: FormatException(sentinel)),
    );
    expect(copied, contains('FormatException'));
    expect(copied, isNot(contains('SENTINEL')));
  });
}
