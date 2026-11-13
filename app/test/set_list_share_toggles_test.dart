import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:compendium_app/src/data/set_list_share_scope.dart';
import 'package:compendium_app/src/export/json_export.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';

import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

final _program = Program(
  id: 'p1',
  title: 'Friday Contra',
  eventDate: DateTime.utc(2026, 3, 9),
  venue: 'Town Hall',
  band: 'The Ripplers',
  caller: 'Isaac',
  slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
  createdAt: _now,
  updatedAt: _now,
);

final _dance = Dance(
  id: 'd1',
  title: "Rory O'More",
  authorIds: const [],
  figures: const [],
  sourceCitations: const [],
  customFields: const [],
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the export menu under a the share scopes with the given toggles.
Future<void> _pump(
  WidgetTester tester, {
  bool title = true,
  bool callerBand = true,
  bool dateVenue = true,
  Directory? dir,
  void Function(ShareParams)? onShare,
}) async {
  final notifiers = [
    ValueNotifier<bool>(title),
    ValueNotifier<bool>(callerBand),
    ValueNotifier<bool>(dateVenue),
  ];
  for (final n in notifiers) {
    addTearDown(n.dispose);
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: ShareSetListTitleScope(
        notifier: notifiers[0],
        child: ShareSetListCallerBandScope(
          notifier: notifiers[1],
          child: ShareSetListDateVenueScope(
            notifier: notifiers[2],
            child: Scaffold(
              appBar: AppBar(
                actions: [
                  ProgramExportMenu(
                    program: _program,
                    titleFor: (_) => "Rory O'More",
                    danceFor: dir == null ? null : (_) => _dance,
                    shareInvoker: (p) async => onShare?.call(p),
                    bundleFileWriter: dir == null
                        ? null
                        : (json, fileName) async {
                            final file = File('${dir.path}/$fileName');
                            file.writeAsStringSync(json);
                            return XFile(
                              file.path,
                              mimeType: 'application/json',
                            );
                          },
                    jsonExportDelivery: JsonExportDelivery(
                      choicePicker: (_) async => JsonExportChoice.share,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('program-export-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  final realUnsupported = isBundleShareUnsupported;
  setUp(() => isBundleShareUnsupported = () => false);
  tearDown(() => isBundleShareUnsupported = realUnsupported);

  testWidgets('all toggles on: the shared set list is unchanged', (
    tester,
  ) async {
    ShareParams? shared;
    await _pump(tester, onShare: (p) => shared = p);
    await _choose(tester, 'Share set list (text)');

    expect(shared!.subject, 'Friday Contra');
    expect(shared!.text, contains('Friday Contra'));
    expect(shared!.text, contains('Town Hall'));
    expect(shared!.text, contains('Band: The Ripplers'));
    expect(shared!.text, contains('Caller: Isaac'));
  });

  testWidgets('all toggles off: the shared set list drops the title (and '
      'subject), caller, band, date and venue', (tester) async {
    ShareParams? shared;
    await _pump(
      tester,
      title: false,
      callerBand: false,
      dateVenue: false,
      onShare: (p) => shared = p,
    );
    await _choose(tester, 'Share set list (text)');

    expect(shared!.subject, isNull);
    expect(shared!.text, "1. Rory O'More");
  });

  testWidgets('each toggle drops only its own lines', (tester) async {
    ShareParams? shared;
    await _pump(tester, callerBand: false, onShare: (p) => shared = p);
    await _choose(tester, 'Share set list (text)');
    expect(shared!.text, isNot(contains('Band:')));
    expect(shared!.text, isNot(contains('Caller:')));
    expect(shared!.text, contains('Friday Contra'));
    expect(shared!.text, contains('Town Hall'));

    await _pump(tester, dateVenue: false, onShare: (p) => shared = p);
    await _choose(tester, 'Share set list (text)');
    expect(shared!.text, isNot(contains('Town Hall')));
    expect(shared!.text, isNot(contains('2026')));
    expect(shared!.text, contains('Caller: Isaac'));
  });

  testWidgets('Copy set list follows the toggles', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    await _pump(tester, title: false);
    await _choose(tester, 'Copy set list');

    expect(copied, isNot(contains('Friday Contra')));
    expect(copied, contains('Caller: Isaac'));
  });

  for (final (label, extension) in [
    ('Share (program + dances)', '.ccshare'),
    ('Export as JSON file', '.json'),
  ]) {
    testWidgets('$label still carries the whole program with every toggle '
        'off', (tester) async {
      final dir = Directory.systemTemp.createTempSync('set_list_share_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      ShareParams? shared;
      await _pump(
        tester,
        title: false,
        callerBand: false,
        dateVenue: false,
        dir: dir,
        onShare: (p) => shared = p,
      );
      await _choose(tester, label);

      final file = shared!.files!.single;
      expect(file.path, endsWith(extension));
      final program = decodeArchive(
        File(file.path).readAsStringSync(),
      ).archive.programs.single;
      expect(program.title, 'Friday Contra');
      expect(program.caller, 'Isaac');
      expect(program.band, 'The Ripplers');
      expect(program.venue, 'Town Hall');
      expect(program.eventDate, isNotNull);
      // The bundle's subject is the title regardless of the set-list toggle.
      expect(shared!.subject, 'Friday Contra');
    });
  }
}
