import 'package:compendium_app/src/utils/launch_external_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/fake_url_launcher.dart';

void main() {
  group('tryParseHttpUrl', () {
    test('accepts http and https URLs', () {
      expect(
        tryParseHttpUrl('https://example.com/x')?.toString(),
        'https://example.com/x',
      );
      expect(tryParseHttpUrl('http://example.com')?.host, 'example.com');
    });

    test('trims surrounding whitespace', () {
      expect(tryParseHttpUrl('  https://example.com  ')?.host, 'example.com');
    });

    test('rejects null, empty, and whitespace', () {
      expect(tryParseHttpUrl(null), isNull);
      expect(tryParseHttpUrl(''), isNull);
      expect(tryParseHttpUrl('   '), isNull);
    });

    test('rejects non-http(s) schemes', () {
      expect(tryParseHttpUrl('mailto:a@b.com'), isNull);
      expect(tryParseHttpUrl('ftp://example.com'), isNull);
      expect(tryParseHttpUrl('javascript:alert(1)'), isNull);
    });

    test('rejects scheme-less or hostless strings', () {
      expect(tryParseHttpUrl('example.com'), isNull);
      expect(tryParseHttpUrl('https://'), isNull);
    });
  });

  group('launchExternalUrl', () {
    late FakeUrlLauncher fake;

    setUp(() {
      fake = installFakeUrlLauncher();
    });

    Future<BuildContext> pumpContext(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return ctx;
    }

    testWidgets('launches a valid URL externally', (tester) async {
      final ctx = await pumpContext(tester);
      await launchExternalUrl(ctx, 'https://example.com/x');
      expect(fake.lastLaunchedUrl, 'https://example.com/x');
      expect(
        fake.launchedModes.single,
        PreferredLaunchMode.externalApplication,
      );
    });

    testWidgets('shows a SnackBar for an invalid URL and does not launch', (
      tester,
    ) async {
      final ctx = await pumpContext(tester);
      await launchExternalUrl(ctx, 'not a url');
      await tester.pump();
      expect(fake.launchedUrls, isEmpty);
      expect(find.text("Couldn't open link"), findsOneWidget);
    });

    testWidgets('shows a SnackBar when the launcher returns false', (
      tester,
    ) async {
      fake.launchResult = false;
      final ctx = await pumpContext(tester);
      await launchExternalUrl(ctx, 'https://example.com');
      await tester.pump();
      expect(find.text("Couldn't open link"), findsOneWidget);
    });

    testWidgets('shows a SnackBar when the launcher throws', (tester) async {
      fake.throwOnLaunch = Exception('boom');
      final ctx = await pumpContext(tester);
      await launchExternalUrl(ctx, 'https://example.com');
      await tester.pump();
      expect(find.text("Couldn't open link"), findsOneWidget);
    });
  });
}
