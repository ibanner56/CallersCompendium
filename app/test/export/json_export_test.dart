import 'dart:io';

import 'package:compendium_app/src/export/json_export.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:compendium_app/src/widgets/json_export_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('choice dialog returns the selected delivery', (tester) async {
    JsonExportChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showJsonExportChoiceDialog(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Copy raw JSON'), findsOneWidget);
    await tester.tap(find.text('Copy raw JSON'));
    await tester.pumpAndSettle();

    expect(choice, JsonExportChoice.copy);
  });

  testWidgets('dismissing the choice dialog returns null', (tester) async {
    JsonExportChoice? choice = JsonExportChoice.save;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showJsonExportChoiceDialog(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(choice, isNull);
  });

  test('desktop save writes exact JSON to selected path', () async {
    final directory = await Directory.systemTemp.createTemp('json-save-test');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/dance.json';
    var pickerCalls = 0;

    final result = await saveJsonBundle(
      '{"canonical":true}',
      'dance.json',
      isDesktop: () => true,
      saveLocationPicker:
          ({
            suggestedName,
            acceptedTypeGroups,
            initialDirectory,
            canCreateDirectories,
          }) async {
            pickerCalls++;
            expect(suggestedName, 'dance.json');
            expect(acceptedTypeGroups!.single.extensions, ['json']);
            return FileSaveLocation(path);
          },
    );

    expect(pickerCalls, 1);
    expect(result, isNotNull);
    expect(result!.fileName, 'dance.json');
    expect(await File(path).readAsString(), '{"canonical":true}');
  });

  test('desktop picker cancellation performs no write', () async {
    var staged = false;

    final result = await saveJsonBundle(
      '{"canonical":true}',
      'dance.json',
      isDesktop: () => true,
      saveLocationPicker:
          ({
            suggestedName,
            acceptedTypeGroups,
            initialDirectory,
            canCreateDirectories,
          }) async => null,
      stageFile: (json, fileName) async {
        staged = true;
        return XFile('/tmp/$fileName');
      },
    );

    expect(result, isNull);
    expect(staged, isFalse);
  });

  test(
    'repeated desktop saves preserve the first export with a suffix',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'json-collision-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/dance.json';
      Future<FileSaveLocation?> pickLocation({
        String? suggestedName,
        List<XTypeGroup>? acceptedTypeGroups,
        String? initialDirectory,
        bool? canCreateDirectories,
      }) async => FileSaveLocation(path);

      final first = await saveJsonBundle(
        '{"version":1}',
        'dance.json',
        isDesktop: () => true,
        saveLocationPicker: pickLocation,
      );
      final second = await saveJsonBundle(
        '{"version":2}',
        'dance.json',
        isDesktop: () => true,
        isMacOS: () => false,
        saveLocationPicker: pickLocation,
      );

      expect(first!.path, path);
      expect(second!.path, '${directory.path}/dance (1).json');
      expect(await File(path).readAsString(), '{"version":1}');
      expect(await File(second.path).readAsString(), '{"version":2}');
    },
  );

  test('macOS save writes back to the exact selected path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'json-macos-save-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/dance.json';
    await File(path).writeAsString('{"version":1}');

    final result = await saveJsonBundle(
      '{"version":2}',
      'dance.json',
      isDesktop: () => true,
      isMacOS: () => true,
      saveLocationPicker:
          ({
            suggestedName,
            acceptedTypeGroups,
            initialDirectory,
            canCreateDirectories,
          }) async => FileSaveLocation(path),
    );

    expect(result!.path, path);
    expect(result.fileName, 'dance.json');
    expect(await File(path).readAsString(), '{"version":2}');
    expect(await File('${directory.path}/dance (1).json').exists(), isFalse);
  });

  test(
    'mobile save stages exact JSON and returns platform destination',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'json-mobile-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      String? stagedJson;
      String? stagedName;
      String? sourcePath;

      final result = await saveJsonBundle(
        '{"canonical":true}',
        'dance.json',
        isDesktop: () => false,
        stageFile: (json, fileName) async {
          stagedJson = json;
          stagedName = fileName;
          final path = '${directory.path}/$fileName';
          await File(path).writeAsString(json);
          return XFile(path);
        },
        mobileSaveFile: (path) async {
          sourcePath = path;
          return 'content://downloads/renamed-dance.json';
        },
      );

      expect(stagedJson, '{"canonical":true}');
      expect(stagedName, 'dance.json');
      expect(sourcePath, '${directory.path}/dance.json');
      expect(result, isNotNull);
      expect(result!.path, 'content://downloads/renamed-dance.json');
      expect(result.fileName, 'renamed-dance.json');
      expect(await File(sourcePath!).exists(), isFalse);
    },
  );

  test('Android save does not display an opaque provider identifier', () async {
    final directory = await Directory.systemTemp.createTemp(
      'json-android-save-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    String? stagedPath;

    final result = await saveJsonBundle(
      '{"canonical":true}',
      'dance.json',
      isDesktop: () => false,
      isAndroid: () => true,
      stageFile: (json, fileName) async {
        stagedPath = '${directory.path}/$fileName';
        await File(stagedPath!).writeAsString(json);
        return XFile(stagedPath!);
      },
      mobileSaveFile: (_) async => '/document/msf:123',
    );

    expect(result, isNotNull);
    expect(result!.path, '/document/msf:123');
    expect(result.fileName, isNull);
    expect(await File(stagedPath!).exists(), isFalse);
  });

  test('mobile save cancellation deletes its staged export', () async {
    final directory = await Directory.systemTemp.createTemp(
      'json-mobile-cancel-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    String? stagedPath;

    final result = await saveJsonBundle(
      '{"canonical":true}',
      'dance.json',
      isDesktop: () => false,
      stageFile: (json, fileName) async {
        stagedPath = '${directory.path}/$fileName';
        await File(stagedPath!).writeAsString(json);
        return XFile(stagedPath!);
      },
      mobileSaveFile: (_) async => null,
    );

    expect(result, isNull);
    expect(await File(stagedPath!).exists(), isFalse);
  });
}
