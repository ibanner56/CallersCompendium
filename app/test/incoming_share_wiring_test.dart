import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/archive_intake_service.dart';
import 'package:compendium_app/src/data/incoming_file_channel.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'package:compendium_app/src/screens/contradb_program_import_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// A [WindowService] whose restore does nothing (no real window under test).
class _NoopWindowService extends WindowService {
  _NoopWindowService(super.settings);
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}

/// A fake [IncomingFileChannel] that delivers a caller-chosen cold-start file
/// path and/or shared URL — no real platform channel is touched.
class _FakeIncomingFileChannel extends IncomingFileChannel {
  _FakeIncomingFileChannel({this.initialPath, this.initialSharedUrl});

  final String? initialPath;
  final String? initialSharedUrl;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final StreamController<String> _urlController =
      StreamController<String>.broadcast();

  @override
  void start() {}

  @override
  Stream<String> get files => _controller.stream;

  @override
  Stream<String> get urls => _urlController.stream;

  @override
  Future<String?> initialFile() async => initialPath;

  @override
  Future<String?> initialUrl() async => initialSharedUrl;

  @override
  void dispose() {
    unawaited(_controller.close());
    unawaited(_urlController.close());
  }
}

String _validBundleJson() => encodeArchive(
  CompendiumArchive(
    exportedAt: DateTime.utc(2026, 7, 15),
    dances: [
      Dance(
        id: 'd1',
        title: 'Simplicity Swing',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ],
    programs: [
      Program(
        id: 'p1',
        title: 'Shared Spring Fling',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
      ),
    ],
  ),
);

AppData _openAppData() {
  final appData = AppData(
    CompendiumDatabase(
      NativeDatabase.memory(),
      // See [CompendiumDatabase.closeStreamsSynchronously]: widget tests run
      // under fake_async, which fails on drift's stream-close timer.
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(appData.close);
  return appData;
}

/// An in-memory byte reader so intake runs without real file I/O — a real disk
/// read would be started inside the test's faked-time zone and never complete.
ArchiveByteReader _readerFor(String contents) =>
    (_) async => Uint8List.fromList(utf8.encode(contents));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // Booting the full app keeps the User Guide's doc FutureBuilder alive; the
  // root bundle caches parsed results as SynchronousFutures which otherwise
  // stall pumpAndSettle. Clearing the cache before each test lets it settle
  // (mirrors startup_sequence_test).
  setUp(rootBundle.clear);

  testWidgets(
    'issue #432: a shared bundle opened at launch routes to the import review '
    'screen and commits nothing until the user confirms',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          incomingFileChannel: _FakeIncomingFileChannel(
            initialPath: '/shared/bundle.json',
          ),
          incomingFileReader: _readerFor(_validBundleJson()),
        ),
      );
      // Bootstrap builds the ready app, which schedules the cold-start intake;
      // the in-memory validation + review-screen navigation settle within these
      // pumps.
      await tester.pumpAndSettle();

      // The untrusted bundle lands on the review/consent screen — never the old
      // auto-open ProgramSummaryScreen — and NOTHING is written yet.
      expect(find.byType(ImportReviewScreen), findsOneWidget);
      expect(await appData.repositories.programs.listAll(), isEmpty);
      expect(await appData.repositories.dances.listAll(), isEmpty);
    },
  );

  testWidgets('a malformed shared file is rejected with a snackbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = _openAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: _NoopWindowService(appData.repositories.settings),
        incomingFileChannel: _FakeIncomingFileChannel(
          initialPath: '/shared/bundle.json',
        ),
        incomingFileReader: _readerFor('this is not a compendium archive'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shared-import-error')), findsOneWidget);
    expect(find.byType(ImportReviewScreen), findsNothing);
    expect(await appData.repositories.programs.listAll(), isEmpty);
  });

  testWidgets(
    'issue #343: a shared ContraDB program URL opens the import screen '
    'pre-filled and auto-fetching',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          incomingFileChannel: _FakeIncomingFileChannel(
            initialSharedUrl: 'https://contradb.com/programs/33',
          ),
          // Seam-backed so the screen's auto-fetch touches no network.
          incomingUrlFetcher: (_) async => _sharedProgramHtml,
        ),
      );
      await tester.pumpAndSettle();

      // Routed to the ContraDB program import screen, pre-filled + auto-fetched.
      expect(find.byType(ContraDbProgramImportScreen), findsOneWidget);
      expect(find.text('https://contradb.com/programs/33'), findsOneWidget);
      expect(find.text('Courageous Soul'), findsWidgets);
    },
  );

  testWidgets(
    'issue #343: a Firefox-style "title\\nurl" share still opens the import '
    'screen pre-filled with the extracted URL',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          incomingFileChannel: _FakeIncomingFileChannel(
            initialSharedUrl:
                'A Lovely Contra Program\nhttps://contradb.com/programs/33',
          ),
          incomingUrlFetcher: (_) async => _sharedProgramHtml,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ContraDbProgramImportScreen), findsOneWidget);
      // The extracted, canonical URL (not the raw "title\nurl") is pre-filled.
      expect(find.text('https://contradb.com/programs/33'), findsOneWidget);
    },
  );

  testWidgets(
    'issue #343: a malicious / non-ContraDB shared URL is rejected with a '
    'snackbar and never opens the import screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          incomingFileChannel: _FakeIncomingFileChannel(
            initialSharedUrl: 'http://evil.com/programs/1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('shared-url-import-error')),
        findsOneWidget,
      );
      expect(find.byType(ContraDbProgramImportScreen), findsNothing);
      expect(await appData.repositories.programs.listAll(), isEmpty);
    },
  );
}

/// A minimal, real-shaped ContraDB program page for the shared-URL auto-fetch:
/// one linked dance, enough for the preview to populate.
const String _sharedProgramHtml = '''
<html><body>
<div class="programs-show-content"><div class="container"><h1>Barn Dance</h1></div></div>
<div id="activity-1" class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title"><a href="/dances/185">Courageous Soul</a></h2>
</div>
</body></html>
''';
