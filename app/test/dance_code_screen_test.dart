import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/dance_code.dart';
import 'package:compendium_app/src/export/dance_share_bundle.dart';
import 'package:compendium_app/src/export/json_export.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:compendium_app/src/widgets/dance_code_view.dart';
import 'package:compendium_app/src/widgets/dance_export_actions.dart';
import 'package:compendium_app/src/widgets/dance_export_menu.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';

/// Show code (#2334): the action that builds the code, the screen that shows
/// it, and the two places it is offered. Decoding what the screen really
/// draws is in `dance_code_render_test.dart`.

final _now = DateTime.utc(2026, 11, 22);

// Values that must never reach a code (each is searched for below).
const _email = 'private.caller@example.com';
const _city = 'PRIVATE-CITY-NAME';
const _hiddenFieldValue = 'PRIVATE-FIELD-VALUE';
const _figureNote = 'PRIVATE-FIGURE-NOTE';

// Values that must reach it (positive controls: the search can find things).
const _sharedFieldValue = 'SHARED-FIELD-VALUE';

final _author = Choreographer(
  id: 'c1',
  name: 'Public Author',
  email: _email,
  location: _city,
  deceased: true,
);

final _sharedField = CustomFieldDef(
  id: 'f1',
  key: 'teach',
  label: 'Teaching',
  type: CustomFieldType.text,
  shareable: true,
);

final _hiddenField = CustomFieldDef(
  id: 'f2',
  key: 'hidden',
  label: 'Hidden',
  type: CustomFieldType.text,
  shareable: false,
);

final _userFigure = UserGlossaryEntry(
  id: 'u1',
  kindName: UserGlossaryEntryKind.customFigure.name,
  name: 'my own figure',
  definition: 'A figure.',
  description: 'Of your own.',
  notes: _figureNote,
  payload: const {
    'form': 'contra',
    'template': '{move}',
    'defaultBeats': 8,
    'params': <Object?>[],
  },
  createdAt: _now,
);

Dance _dance({String title = 'Rory O\'More', String walkthrough = ''}) => Dance(
  id: 'd1',
  title: title,
  authorIds: const ['c1'],
  rating: 4,
  walkthrough: walkthrough,
  customFields: [
    CustomFieldValue(fieldId: 'f1', value: _sharedFieldValue),
    CustomFieldValue(fieldId: 'f2', value: _hiddenFieldValue),
  ],
  figures: [
    userFigureUseFigure(id: 'u1', args: const {}, text: 'my own figure'),
  ],
  createdAt: _now,
  updatedAt: _now,
);

DanceExportActions _actions(
  Dance dance, {
  ShareInvoker? shareInvoker,
  BundleFileWriter? bundleFileWriter,
  JsonExportDelivery? jsonExportDelivery,
}) => DanceExportActions(
  dance: dance,
  dialect: Dialect.canonical,
  authorNames: const ['Public Author'],
  formationLabel: 'Duple improper',
  statusLabel: 'Active',
  canonicalizeDiscouragedTerms: false,
  choreographersById: {'c1': _author},
  customFieldsById: {'f1': _sharedField, 'f2': _hiddenField},
  userFigureFor: (id) => id == 'u1' ? _userFigure : null,
  shareInvoker: shareInvoker,
  bundleFileWriter: bundleFileWriter,
  jsonExportDelivery: jsonExportDelivery,
  now: () => _now,
);

/// The bundle the Share dance file action would send for [dance].
String _bundleFor(Dance dance) => buildDanceShareBundle(
  dance,
  now: _now,
  choreographerFor: (id) => id == 'c1' ? _author : null,
  tagFor: (_) => null,
  publishedSourceFor: (_) => null,
  customFieldFor: (id) => {'f1': _sharedField, 'f2': _hiddenField}[id],
  userFigureFor: (id) => id == 'u1' ? _userFigure : null,
);

Future<void> _pumpHost(WidgetTester tester, DanceExportActions actions) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('go'),
              onPressed: () => actions.showCode(
                Navigator.of(context),
                ScaffoldMessenger.of(context),
                AppLocalizations.of(context),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Deterministic text that does not compress: far too long for any code.
String _incompressible(int length) {
  var state = 24680;
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,;:!?';
  final codes = <int>[];
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    codes.add(alphabet.codeUnitAt((state >> 8) % alphabet.length));
  }
  return String.fromCharCodes(codes);
}

class _CountingHttpOverrides extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return super.createHttpClient(context);
  }
}

void main() {
  final realBundleShareUnsupported = isBundleShareUnsupported;
  setUp(() => isBundleShareUnsupported = () => false);
  tearDown(() => isBundleShareUnsupported = realBundleShareUnsupported);

  group('Show code action', () {
    testWidgets('the code holds exactly the dance file, and nothing private', (
      tester,
    ) async {
      final dance = _dance();
      await _pumpHost(tester, _actions(dance));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      final screen = tester.widget<DanceCodeScreen>(
        find.byType(DanceCodeScreen),
      );
      final carried = decodeDanceLink(screen.plan.link);

      // The same bytes Share dance file builds, clock fixed.
      expect(carried, _bundleFor(dance));

      // Positive controls: the search can find what does travel, and each
      // private value really is on the dance and in the unfiltered export.
      expect(carried, contains('Public Author'));
      expect(carried, contains(_sharedFieldValue));
      expect(carried, contains('my own figure'));
      final unfiltered = encodeArchive(
        CompendiumArchive(
          exportedAt: _now,
          dances: [dance],
          choreographers: [_author],
          customFields: [_sharedField, _hiddenField],
        ),
        mode: ArchiveSerializationMode.backup,
      );
      for (final secret in [_email, _city, _hiddenFieldValue]) {
        expect(unfiltered, contains(secret), reason: 'control for $secret');
      }
      expect(dance.rating, 4);
      expect(unfiltered, contains('"rating":4'));

      // None of them is in the code. The figure note is the weakest probe: the
      // archive encoder never writes a user figure's notes in any mode, so no
      // bypass of `_buildBundle` could put it back. It guards one thing, the
      // share-mode encoder starting to emit notes, and has no control above.
      for (final secret in [_email, _city, _hiddenFieldValue, _figureNote]) {
        expect(carried, isNot(contains(secret)), reason: secret);
      }
      expect(carried, isNot(contains('"rating"')));
      expect(carried, isNot(contains('"deceased":true')));
    });

    testWidgets('shows no code for a dance that cannot be built, and says so', (
      tester,
    ) async {
      // The dance names a custom field the lookup does not know: the bundle
      // builder refuses it, exactly as Share dance file would.
      final dance = _dance();
      final actions = DanceExportActions(
        dance: dance,
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
        canonicalizeDiscouragedTerms: false,
        choreographersById: {'c1': _author},
        now: () => _now,
      );
      await _pumpHost(tester, actions);
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      expect(find.byType(DanceCodeScreen), findsNothing);
      expect(find.byType(DanceCodeTooLongScreen), findsNothing);
      expect(
        find.text(
          "Couldn't show the code. Your dance is unchanged. Try again.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a dance too long for any code offers the dance file', (
      tester,
    ) async {
      isBundleShareUnsupported = () => true; // observable through the saver
      final saved = <String>[];
      final dance = _dance(
        title: 'A very long dance',
        walkthrough: _incompressible(20000),
      );
      await _pumpHost(
        tester,
        _actions(
          dance,
          jsonExportDelivery: JsonExportDelivery(
            saveInvoker: (json, fileName) async {
              saved.add(fileName);
              return JsonSaveResult(path: '', fileName: fileName);
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      expect(find.byType(DanceCodeScreen), findsNothing);
      expect(find.byKey(const ValueKey('dance-code-too-long')), findsOneWidget);
      // On Linux there is no file share sheet, so the button says Save.
      expect(find.text('Save dance file…'), findsOneWidget);
      expect(find.text('Share dance file'), findsNothing);
      expect(saved, isEmpty, reason: 'nothing is shared until asked');

      await tester.tap(find.byKey(const ValueKey('dance-code-share-file')));
      await tester.pumpAndSettle();

      expect(saved, ['A_very_long_dance.ccshare']);
    });

    testWidgets('the too-long notice shares the file from its own button', (
      tester,
    ) async {
      final shares = <ShareParams>[];
      await _pumpHost(
        tester,
        _actions(
          _dance(title: 'Long one', walkthrough: _incompressible(20000)),
          shareInvoker: (params) async => shares.add(params),
          bundleFileWriter: (json, fileName) async =>
              XFile.fromData(Uint8List(0), name: fileName),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(find.text('Share dance file'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dance-code-share-file')));
      await tester.pumpAndSettle();

      expect(shares, hasLength(1));
      // The share sheet anchors to the button the user pressed, not to where
      // the Export button was on the screen before.
      expect(
        shares.single.sharePositionOrigin,
        tester.getRect(find.byKey(const ValueKey('dance-code-share-file'))),
      );
    });

    testWidgets('makes no HTTP client while the code shows', (tester) async {
      final overrides = _CountingHttpOverrides();
      final previous = HttpOverrides.current;
      HttpOverrides.global = overrides;
      addTearDown(() => HttpOverrides.global = previous);

      // Control: the counter does see a client being made.
      HttpClient().close();
      expect(overrides.clients, 1);
      overrides.clients = 0;

      await _pumpHost(tester, _actions(_dance()));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      expect(find.byType(DanceCodeScreen), findsOneWidget);
      // This sees `dart:io` HTTP clients only, which is how Dart code makes a
      // request; it cannot see a raw socket or a plugin.
      expect(overrides.clients, 0);
    });
  });

  group('the code screen', () {
    testWidgets('keeps the screen awake while it shows, and lets go on exit', (
      tester,
    ) async {
      final wakelock = installCountingWakelock();
      await _pumpHost(tester, _actions(_dance()));
      expect(wakelock.outstanding, 0);

      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(find.byType(DanceCodeScreen), findsOneWidget);
      expect(wakelock.outstanding, 1);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DanceCodeScreen), findsNothing);
      expect(wakelock.outstanding, 0);
    });

    testWidgets('the too-long notice does not hold the screen awake', (
      tester,
    ) async {
      final wakelock = installCountingWakelock();
      await _pumpHost(
        tester,
        _actions(_dance(walkthrough: _incompressible(20000))),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      expect(find.byType(DanceCodeTooLongScreen), findsOneWidget);
      expect(wakelock.toggles, isEmpty);
    });

    // Real phones are not all 3x: 2.625 and 1.75 are common Android densities.
    for (final (size, dpr) in const [
      (Size(360, 780), 3.0),
      (Size(412, 915), 2.625),
      (Size(360, 640), 1.75),
    ]) {
      testWidgets('fits a ${size.width.toInt()} wide phone at ${dpr}x density '
          'and 2x text with a long title', (tester) async {
        tester.view
          ..physicalSize = size * dpr
          ..devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final handle = tester.ensureSemantics();
        try {
          final title = 'A dance with a really quite long title ' * 6;
          await _pumpHost(tester, _actions(_dance(title: title)));
          await tester.tap(find.byKey(const ValueKey('go')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final code = tester.getSize(find.byKey(const ValueKey('dance-code')));
          expect(code.width, code.height, reason: 'a code is a square');
          expect(code.width, lessThanOrEqualTo(size.width));
          // Every module is a whole number of device pixels wide.
          final plan = tester
              .widget<DanceCodeScreen>(find.byType(DanceCodeScreen))
              .plan;
          final span = plan.moduleCount + 8;
          final modulePixels = code.width * dpr / span;
          expect(modulePixels, closeTo(modulePixels.roundToDouble(), 1e-6));
          expect(find.bySemanticsLabel('QR code for $title'), findsOneWidget);
        } finally {
          handle.dispose();
        }
      });
    }
  });

  group('a window too small to scan from', () {
    testWidgets('still draws a square code that stays inside it', (
      tester,
    ) async {
      // Narrower than one device pixel per module: nothing could scan this,
      // but the screen must not overflow or draw a lopsided code.
      tester.view
        ..physicalSize = const Size(120, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpHost(tester, _actions(_dance()));
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final code = tester.getSize(find.byKey(const ValueKey('dance-code')));
      expect(code.width, code.height);
      expect(code.width, lessThanOrEqualTo(120 - 32));
    });
  });

  group('pixel snapping', () {
    // A canvas whose origin is at (tx, ty) device pixels, scaled by `scale`.
    Float64List transform(double tx, double ty, double scale) =>
        (Matrix4.translationValues(
          tx,
          ty,
          0,
        )..scaleByDouble(scale, scale, 1, 1)).storage;

    test('moves a fractional origin onto a whole device pixel', () {
      for (final (tx, ty, scale) in const [
        (10.4, 20.5, 2.625),
        (0.5, 0.5, 1.0),
        (133.5, 47.25, 3.0),
        (7.9, 3.1, 1.75),
      ]) {
        final shift = pixelSnapShift(transform(tx, ty, scale));
        final snappedX = tx + shift.dx * scale;
        final snappedY = ty + shift.dy * scale;
        expect(snappedX, closeTo(snappedX.roundToDouble(), 1e-9));
        expect(snappedY, closeTo(snappedY.roundToDouble(), 1e-9));
        expect(shift.dx.abs() * scale, lessThanOrEqualTo(0.5 + 1e-9));
      }
    });

    test('leaves a whole-pixel origin where it is', () {
      expect(pixelSnapShift(transform(12, 30, 3)), Offset.zero);
    });
  });

  group('where it is offered', () {
    testWidgets('the Export menu opens the code for that dance', (
      tester,
    ) async {
      final dance = _dance(title: 'Menu dance');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                DanceExportMenu(
                  dance: dance,
                  dialect: Dialect.canonical,
                  authorNames: const [],
                  formationLabel: 'Duple improper',
                  statusLabel: 'Active',
                  choreographersById: {'c1': _author},
                  customFieldsById: {'f1': _sharedField, 'f2': _hiddenField},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dance-export-show-code')));
      await tester.pumpAndSettle();

      expect(find.byType(DanceCodeScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('dance-code-title')))
            .data,
        'Menu dance',
      );
    });
  });
}
