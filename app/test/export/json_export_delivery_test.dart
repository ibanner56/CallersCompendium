import 'package:compendium_app/src/export/json_export.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import '../support/l10n_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool Function() savedUnsupported;

  setUp(() {
    savedUnsupported = isBundleShareUnsupported;
    // Force the share-sheet branch so the test is platform-independent.
    isBundleShareUnsupported = () => false;
  });

  tearDown(() => isBundleShareUnsupported = savedUnsupported);

  Future<void> pumpAndDeliver(
    WidgetTester tester,
    JsonExportDelivery delivery,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => delivery.deliver(
                context,
                json: '{"a":1}',
                fileName: 'x.json',
                subject: 'Subject',
                sharePositionOrigin: null,
                source: 'json_export_delivery_test',
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
  }

  group('deliver routes save/copy/share through guardExport', () {
    testWidgets('save hits the seam and shows the saved snackbar', (
      tester,
    ) async {
      String? savedJson;
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.save,
          saveInvoker: (json, name) async {
            savedJson = json;
            return JsonSaveResult(path: '/tmp/$name', fileName: name);
          },
        ),
      );
      expect(savedJson, '{"a":1}');
      expect(find.text('"x.json" saved to /tmp/x.json.'), findsOneWidget);
    });

    testWidgets('save without a file name shows the generic snackbar', (
      tester,
    ) async {
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.save,
          saveInvoker: (json, name) async =>
              const JsonSaveResult(path: '', fileName: null),
        ),
      );
      expect(find.text('JSON file saved.'), findsOneWidget);
    });

    testWidgets('a cancelled save shows nothing', (tester) async {
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.save,
          saveInvoker: (json, name) async => null,
        ),
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('copy hits the seam and shows the copied snackbar', (
      tester,
    ) async {
      String? copied;
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.copy,
          clipboardWriter: (json) async => copied = json,
        ),
      );
      expect(copied, '{"a":1}');
      expect(find.text('JSON copied to clipboard.'), findsOneWidget);
    });

    testWidgets('share hands the file to the share seam', (tester) async {
      String? subject;
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.share,
          bundleFileWriter: (json, name) async => XFile('/tmp/$name'),
          shareInvoker: (params) async => subject = params.subject,
        ),
      );
      expect(subject, 'Subject');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a dismissed choice does nothing', (tester) async {
      var touched = false;
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => null,
          saveInvoker: (json, name) async {
            touched = true;
            return null;
          },
          clipboardWriter: (json) async => touched = true,
        ),
      );
      expect(touched, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('deliver reports a throwing seam with the matching error snackbar', () {
    testWidgets('save', (tester) async {
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.save,
          saveInvoker: (json, name) async => throw StateError('boom'),
        ),
      );
      expect(find.text("Couldn't save this JSON file."), findsOneWidget);
    });

    testWidgets('copy', (tester) async {
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.copy,
          clipboardWriter: (json) async => throw StateError('boom'),
        ),
      );
      expect(find.text("Couldn't copy this JSON."), findsOneWidget);
    });

    testWidgets('share', (tester) async {
      await pumpAndDeliver(
        tester,
        JsonExportDelivery(
          choicePicker: (_) async => JsonExportChoice.share,
          bundleFileWriter: (json, name) async => XFile('/tmp/$name'),
          shareInvoker: (params) async => throw StateError('boom'),
        ),
      );
      expect(find.text("Couldn't share this JSON file."), findsOneWidget);
    });
  });
}
