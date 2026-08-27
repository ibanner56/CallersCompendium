import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({
  String title = 'Friday Contra',
  String? venueId,
  List<ProgramSlot> slots = const [],
  bool hideAlternates = false,
}) => Program(
  id: 'p1',
  title: title,
  eventDate: DateTime.utc(2026, 3, 9),
  venue: 'Town Hall',
  venueId: venueId,
  band: 'The Ripplers',
  caller: 'Isaac',
  dancerLevel: 'All',
  notes: 'Bring water.',
  slots: slots,
  hideAlternates: hideAlternates,
  createdAt: _now,
  updatedAt: _now,
);

/// A fully-populated linked venue used to prove export-side resolution and the
/// richer PDF venue block.
final _venue = Venue(
  id: 'v1',
  name: 'Grange Hall',
  address1: '123 Main St',
  address2: 'Room 2',
  city: 'Montpelier',
  stateProv: 'VT',
  country: 'USA',
  postalCode: '05602',
  plus4: '1234',
  website: 'https://grange.example',
  sponsor: 'Capital City Grange',
  genericSchedule: '2nd Saturdays',
  price: '\$12',
  contact1Name: 'Pat Caller',
  contact1Phone: '555-0100',
  contact1Email: 'pat@example.com',
);

String? _titles(String id) =>
    const {'d1': 'Rory O\'More', 'd2': 'The Nice Combination'}[id];

final _dances = <String, Dance>{
  'd1': Dance(
    id: 'd1',
    title: 'Rory O\'More',
    authorIds: const [],
    figures: [
      Figure(move: 'swing', params: {'beats': 16, 'who': 'partners'}),
    ],
    sourceCitations: const [],
    customFields: const [],
    createdAt: _now,
    updatedAt: _now,
  ),
  'd2': Dance(
    id: 'd2',
    title: 'The Nice Combination',
    authorIds: const [],
    figures: const [],
    sourceCitations: const [],
    customFields: const [],
    createdAt: _now,
    updatedAt: _now,
  ),
};

Dance? _danceFor(String id) => _dances[id];

Future<void> _pumpMenu(
  WidgetTester tester,
  Program program, {
  Map<String, Venue> venuesById = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        appBar: AppBar(
          actions: [
            ProgramExportMenu(
              program: program,
              titleFor: _titles,
              venuesById: venuesById,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Builds a bundle-capable [ProgramExportMenu] wired with test seams: the bundle
/// is written to [dir] and the share call is captured via [onShare] instead of
/// hitting the OS share sheet.
Widget _shareBundleMenu(
  Program program,
  Map<String, Venue> venuesById,
  Directory dir,
  void Function(ShareParams) onShare,
) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: Scaffold(
    appBar: AppBar(
      actions: [
        ProgramExportMenu(
          program: program,
          titleFor: _titles,
          venuesById: venuesById,
          danceFor: _danceFor,
          bundleFileWriter: (json, fileName) async {
            final file = File('${dir.path}/$fileName');
            file.writeAsStringSync(json);
            return XFile(file.path, mimeType: 'application/json');
          },
          shareInvoker: (params) async => onShare(params),
        ),
      ],
    ),
  ),
);

/// Builds a PDF-capable [ProgramExportMenu] whose print/save call is captured
/// via [onExport] (instead of hitting the OS print dialog), so a test can assert
/// whether a PDF would actually be generated. The real [buildProgramPdf] is not
/// invoked — gating is what these tests verify; the *content* of the sanitized
/// venue fed to the builder is asserted at the unit level over
/// `venuesWithSanitizedContact` / `sanitizeVenueForShare`.
Widget _pdfMenu(
  Program program,
  Map<String, Venue> venuesById,
  void Function() onExport,
) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: Scaffold(
    appBar: AppBar(
      actions: [
        ProgramExportMenu(
          program: program,
          titleFor: _titles,
          venuesById: venuesById,
          pdfLayouter: ({required name, required onLayout}) async => onExport(),
        ),
      ],
    ),
  ),
);

void main() {
  group('ProgramExportMenu', () {
    testWidgets('is present and labeled in an app bar', (tester) async {
      await _pumpMenu(tester, _program());

      final menu = find.byKey(const ValueKey('program-export-menu'));
      expect(menu, findsOneWidget);
      // Labeled (icon + accessible tooltip), not icon-only-color.
      expect(find.byTooltip('Export'), findsOneWidget);
    });

    testWidgets('offers share, copy, and PDF actions', (tester) async {
      await _pumpMenu(tester, _program());

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Share set list (text)'), findsOneWidget);
      expect(find.text('Copy set list'), findsOneWidget);
      expect(find.text('Export / print PDF'), findsOneWidget);
    });

    testWidgets('Copy set list puts the rendered text on the clipboard', (
      tester,
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

      await _pumpMenu(
        tester,
        _program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Friday Contra'));
      expect(clipboardText, contains('1. Rory O\'More'));
      expect(find.text('Set list copied to clipboard.'), findsOneWidget);
    });

    testWidgets('Copy set list resolves a linked venue name over free text', (
      tester,
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

      await _pumpMenu(
        tester,
        _program(venueId: 'v1'),
        venuesById: {'v1': _venue},
      );

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      // The linked venue wins over the free text, but only its public name
      // travels: `Venue.displayName` is `name, address1, city, stateProv,
      // country`, and those seven address columns are classified deviceLocal
      // in the privacy registry, so the export routes the venue through
      // `sanitizeVenueForShare` first (issue #853).
      expect(clipboardText, contains('Grange Hall'));
      expect(clipboardText, isNot(contains('Town Hall')));
      for (final leaked in const [
        '123 Main St',
        'Room 2',
        'Montpelier',
        'VT',
        'USA',
        '05602',
        '1234',
      ]) {
        expect(
          clipboardText,
          isNot(contains(leaked)),
          reason: 'venue address field "$leaked" must not reach a set list',
        );
      }
    });

    testWidgets('Copy set list falls back to free text when link unresolved', (
      tester,
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

      // venueId set but not present in the loaded map → free text wins.
      await _pumpMenu(tester, _program(venueId: 'v1'));

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(clipboardText, contains('Town Hall'));
    });

    testWidgets('Copy set list omits ALTs when hideAlternates is set', (
      tester,
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

      await _pumpMenu(
        tester,
        _program(
          hideAlternates: true,
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
          ],
        ),
      );

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('1. Rory O\'More'));
      expect(clipboardText, isNot(contains('ALT:')));
      expect(clipboardText, isNot(contains('The Nice Combination')));
    });

    testWidgets('surfaces a SnackBar when sharing throws', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(),
                  titleFor: _titles,
                  shareInvoker: (params) async =>
                      throw Exception('no share target'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't share this set list"), findsOneWidget);
    });

    testWidgets('share receives a non-null sharePositionOrigin', (
      tester,
    ) async {
      ShareParams? captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(),
                  titleFor: _titles,
                  shareInvoker: (params) async => captured = params,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.sharePositionOrigin, isNotNull);
    });

    testWidgets('surfaces a SnackBar when the PDF export throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(),
                  titleFor: _titles,
                  pdfLayouter: ({required name, required onLayout}) async =>
                      throw Exception('no printer'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't export this set list"), findsOneWidget);
    });

    testWidgets(
      'offers "Share (program + dances)" only when danceFor is given',
      (tester) async {
        // Without danceFor: no bundle action.
        await _pumpMenu(tester, _program());
        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Share (program + dances)'), findsNothing);
        // Close the menu.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        // With danceFor: the bundle action appears.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ProgramExportMenu(
                    program: _program(),
                    titleFor: _titles,
                    danceFor: _danceFor,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Share (program + dances)'), findsOneWidget);
      },
    );

    testWidgets(
      'shares a single .ccshare bundle file with the program + deduped dances',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('share_bundle_test');
        addTearDown(() => dir.deleteSync(recursive: true));

        ShareParams? captured;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ProgramExportMenu(
                    program: _program(
                      slots: [
                        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
                        ProgramSlot(id: 's2', position: 1, text: 'Break'),
                        ProgramSlot(id: 's3', position: 2, danceId: 'd2'),
                        ProgramSlot(id: 's4', position: 3, danceId: 'd1'),
                      ],
                    ),
                    titleFor: _titles,
                    danceFor: _danceFor,
                    bundleFileWriter: (json, fileName) async {
                      final file = File('${dir.path}/$fileName');
                      file.writeAsStringSync(json);
                      return XFile(file.path, mimeType: 'application/json');
                    },
                    shareInvoker: (params) async => captured = params,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share (program + dances)'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.sharePositionOrigin, isNotNull);
        final files = captured!.files!;
        expect(files, hasLength(1));
        expect(files.single.mimeType, 'application/json');
        expect(files.single.path, endsWith('.ccshare'));

        final archive = decodeArchive(
          File(files.single.path).readAsStringSync(),
        ).archive;
        expect(archive.programs.single.id, 'p1');
        expect(archive.dances.map((d) => d.id).toSet(), {'d1', 'd2'});
        expect(archive.dances, hasLength(2));
      },
    );

    testWidgets('surfaces a SnackBar when the bundle share throws', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('share_bundle_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(
                    slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
                  ),
                  titleFor: _titles,
                  danceFor: _danceFor,
                  bundleFileWriter: (json, fileName) async {
                    final file = File('${dir.path}/$fileName');
                    file.writeAsStringSync(json);
                    return XFile(file.path, mimeType: 'application/json');
                  },
                  shareInvoker: (params) async =>
                      throw Exception('no share target'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share (program + dances)'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't share this program"), findsOneWidget);
    });

    testWidgets(
      'venue with contacts: consent dialog defaults off; contacts omitted',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('share_bundle_test');
        addTearDown(() => dir.deleteSync(recursive: true));

        ShareParams? captured;
        await tester.pumpWidget(
          _shareBundleMenu(
            _program(
              venueId: 'v1',
              slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
            ),
            {'v1': _venue},
            dir,
            (p) => captured = p,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share (program + dances)'));
        await tester.pumpAndSettle();

        // The dialog offers only the populated contact fields (contact 1),
        // and nothing is shared while it is open.
        expect(
          find.byKey(const ValueKey('venue-contact-share-dialog')),
          findsOneWidget,
        );
        expect(find.text('Contact 1 name'), findsOneWidget);
        expect(find.text('Contact 1 phone'), findsOneWidget);
        expect(find.text('Contact 1 email'), findsOneWidget);
        expect(find.text('Contact 2 name'), findsNothing);
        expect(captured, isNull);

        // Confirm without checking anything -> all contacts cleared.
        await tester.tap(
          find.byKey(const ValueKey('venue-contact-share-confirm')),
        );
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        final archive = decodeArchive(
          File(captured!.files!.single.path).readAsStringSync(),
        ).archive;
        final venue = archive.venues.single;
        expect(venue.name, 'Grange Hall');
        expect(venue.contact1Name, isNull);
        expect(venue.contact1Phone, isNull);
        expect(venue.contact1Email, isNull);
      },
    );

    testWidgets('venue with contacts: only checked fields are included', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('share_bundle_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      ShareParams? captured;
      await tester.pumpWidget(
        _shareBundleMenu(
          _program(
            venueId: 'v1',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          {'v1': _venue},
          dir,
          (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share (program + dances)'));
      await tester.pumpAndSettle();

      // Opt only the email in.
      await tester.tap(
        find.byKey(const ValueKey('venue-contact-contact1Email')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('venue-contact-share-confirm')),
      );
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      final venue = decodeArchive(
        File(captured!.files!.single.path).readAsStringSync(),
      ).archive.venues.single;
      expect(venue.contact1Email, 'pat@example.com');
      expect(venue.contact1Name, isNull);
      expect(venue.contact1Phone, isNull);
    });

    testWidgets('venue with contacts: Cancel aborts the share', (tester) async {
      final dir = Directory.systemTemp.createTempSync('share_bundle_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      ShareParams? captured;
      await tester.pumpWidget(
        _shareBundleMenu(
          _program(
            venueId: 'v1',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          {'v1': _venue},
          dir,
          (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share (program + dances)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsNothing,
      );
      expect(captured, isNull, reason: 'Cancel aborts the share');
    });

    testWidgets('venue with contacts: dismissing aborts the share', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('share_bundle_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      ShareParams? captured;
      await tester.pumpWidget(
        _shareBundleMenu(
          _program(
            venueId: 'v1',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          {'v1': _venue},
          dir,
          (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share (program + dances)'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsOneWidget,
      );

      // Tap the barrier (outside the dialog) to dismiss it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsNothing,
      );
      expect(captured, isNull, reason: 'dismiss aborts like Cancel');
    });

    testWidgets(
      'venue without contacts: no dialog, venue embedded and shared',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('share_bundle_test');
        addTearDown(() => dir.deleteSync(recursive: true));

        ShareParams? captured;
        await tester.pumpWidget(
          _shareBundleMenu(
            _program(
              venueId: 'v2',
              slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
            ),
            {
              'v2': Venue(
                id: 'v2',
                name: 'Bare Hall',
                city: 'Montpelier',
                eventName: 'Second Saturday Contra',
              ),
            },
            dir,
            (p) => captured = p,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share (program + dances)'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('venue-contact-share-dialog')),
          findsNothing,
        );
        expect(captured, isNotNull);
        final venue = decodeArchive(
          File(captured!.files!.single.path).readAsStringSync(),
        ).archive.venues.single;
        expect(venue.name, 'Bare Hall');
        // Descriptive fields are `shareable` and travel.
        expect(venue.eventName, 'Second Saturday Contra');
        // The address block is classified deviceLocal, so it is stripped
        // unconditionally — there is no consent path for it (issue #853).
        expect(venue.city, isNull);
      },
    );

    testWidgets('no venueId: no dialog and no venue embedded', (tester) async {
      final dir = Directory.systemTemp.createTempSync('share_bundle_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      ShareParams? captured;
      await tester.pumpWidget(
        _shareBundleMenu(
          _program(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          const {},
          dir,
          (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share (program + dances)'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsNothing,
      );
      expect(captured, isNotNull);
      final archive = decodeArchive(
        File(captured!.files!.single.path).readAsStringSync(),
      ).archive;
      expect(archive.venues, isEmpty);
    });

    testWidgets(
      'PDF export: venue with contacts shows the consent dialog and gates it',
      (tester) async {
        var exports = 0;
        await tester.pumpWidget(
          _pdfMenu(_program(venueId: 'v1'), {'v1': _venue}, () => exports++),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export / print PDF'));
        await tester.pumpAndSettle();

        // The consent dialog gates the export — no PDF is generated yet, and it
        // offers only the venue's populated contact fields (contact 1).
        expect(
          find.byKey(const ValueKey('venue-contact-share-dialog')),
          findsOneWidget,
        );
        expect(find.text('Contact 1 name'), findsOneWidget);
        expect(find.text('Contact 2 name'), findsNothing);
        expect(exports, 0);

        // Confirm without checking anything -> export proceeds (with a venue
        // whose contacts are all cleared; see the unit tests for the redaction).
        await tester.tap(
          find.byKey(const ValueKey('venue-contact-share-confirm')),
        );
        await tester.pumpAndSettle();
        expect(exports, 1);
      },
    );

    testWidgets('PDF export: opting a field in still proceeds', (tester) async {
      var exports = 0;
      await tester.pumpWidget(
        _pdfMenu(_program(venueId: 'v1'), {'v1': _venue}, () => exports++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('venue-contact-contact1Email')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('venue-contact-share-confirm')),
      );
      await tester.pumpAndSettle();

      expect(exports, 1);
    });

    testWidgets('PDF export: Cancel aborts (no PDF generated)', (tester) async {
      var exports = 0;
      await tester.pumpWidget(
        _pdfMenu(_program(venueId: 'v1'), {'v1': _venue}, () => exports++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsNothing,
      );
      expect(exports, 0, reason: 'Cancel aborts the PDF export');
    });

    testWidgets('PDF export: dismissing aborts (no PDF generated)', (
      tester,
    ) async {
      var exports = 0;
      await tester.pumpWidget(
        _pdfMenu(_program(venueId: 'v1'), {'v1': _venue}, () => exports++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsOneWidget,
      );

      // Tap the barrier (outside the dialog) to dismiss it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsNothing,
      );
      expect(exports, 0, reason: 'dismiss aborts like Cancel');
    });

    testWidgets(
      'PDF export: venue without contacts skips the dialog and exports',
      (tester) async {
        var exports = 0;
        await tester.pumpWidget(
          _pdfMenu(_program(venueId: 'v2'), {
            'v2': Venue(id: 'v2', name: 'Bare Hall', city: 'Montpelier'),
          }, () => exports++),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export / print PDF'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('venue-contact-share-dialog')),
          findsNothing,
        );
        expect(exports, 1);
      },
    );

    testWidgets('PDF export: no venueId skips the dialog and exports', (
      tester,
    ) async {
      var exports = 0;
      await tester.pumpWidget(_pdfMenu(_program(), const {}, () => exports++));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('venue-contact-share-dialog')),
        findsNothing,
      );
      expect(exports, 1);
    });
  });

  group('Export as JSON file (issue #853)', () {
    testWidgets('menu lists it between Copy set list and Export / print PDF', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('share_json_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      await tester.pumpWidget(
        _shareBundleMenu(_program(), const {}, dir, (_) {}),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();

      // Document order of the menu's ListTiles is the order the user sees.
      // The issue specifies the JSON action's position exactly, so assert the
      // whole sequence rather than mere presence.
      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(titles, const [
        'Share set list (text)',
        'Share (program + dances)',
        'Copy set list',
        'Export as JSON file',
        'Export / print PDF',
      ]);
    });

    testWidgets('is omitted when there is no dance resolver', (tester) async {
      // Same gate as the bundle action: nothing to embed without `danceFor`.
      await _pumpMenu(tester, _program());

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Export as JSON file'), findsNothing);
    });

    testWidgets('shares a .json file carrying the program and its dances', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('share_json_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      ShareParams? captured;
      await tester.pumpWidget(
        _shareBundleMenu(
          _program(
            slots: [
              ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
              ProgramSlot(id: 's2', position: 1, text: 'Break'),
              ProgramSlot(id: 's3', position: 2, danceId: 'd2'),
            ],
          ),
          const {},
          dir,
          (params) => captured = params,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export as JSON file'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      final files = captured!.files!;
      expect(files, hasLength(1));
      expect(files.single.mimeType, 'application/json');
      expect(files.single.path, endsWith('.json'));
      expect(files.single.path, isNot(endsWith('.ccshare')));
      expect(captured!.fileNameOverrides, ['Friday_Contra.json']);

      final archive = decodeArchive(
        File(files.single.path).readAsStringSync(),
      ).archive;
      expect(archive.programs.single.id, 'p1');
      expect(archive.dances.map((d) => d.id).toSet(), {'d1', 'd2'});
    });

    testWidgets('emits the same payload as the .ccshare action', (
      tester,
    ) async {
      // The whole point of the action is a second *file name* for the existing
      // bytes. If the two payloads ever diverge, a second program JSON format
      // has been introduced by accident — which is exactly what this asserts
      // against.
      final dir = Directory.systemTemp.createTempSync('share_json_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      // Every entity kind the bundle can carry must actually be present, or
      // the comparison is vacuous for the missing ones: a payload fork that
      // dropped, say, the choreographers would compare equal against a fixture
      // whose dances have no authors. So: two dances, one of them credited,
      // a resolvable choreographer, and a linked venue.
      final authored = Dance(
        id: 'd3',
        title: 'Ada\'s Whim',
        authorIds: const ['c1'],
        figures: [
          Figure(move: 'swing', params: const {'beats': 16, 'who': 'partners'}),
        ],
        sourceCitations: const [],
        customFields: const [],
        createdAt: _now,
        updatedAt: _now,
      );
      final choreographer = Choreographer(
        id: 'c1',
        name: 'Ada Caller',
        website: 'https://ada.example',
      );
      final program = _program(
        venueId: 'v1',
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd3'),
        ],
      );

      Future<Map<String, Object?>> payloadFor(String menuLabel) async {
        ShareParams? captured;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ProgramExportMenu(
                    program: program,
                    titleFor: _titles,
                    venuesById: {'v1': _venue},
                    danceFor: (id) => id == 'd3' ? authored : _danceFor(id),
                    choreographerFor: (id) => id == 'c1' ? choreographer : null,
                    bundleFileWriter: (json, fileName) async {
                      final file = File('${dir.path}/$fileName');
                      file.writeAsStringSync(json);
                      return XFile(file.path, mimeType: 'application/json');
                    },
                    shareInvoker: (params) async => captured = params,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(menuLabel));
        await tester.pumpAndSettle();
        // The venue has contact fields, so the consent dialog appears; confirm
        // with nothing ticked, identically for both actions.
        await tester.tap(
          find.byKey(const ValueKey('venue-contact-share-confirm')),
        );
        await tester.pumpAndSettle();

        final raw = File(captured!.files!.single.path).readAsStringSync();
        return jsonDecode(raw) as Map<String, Object?>
          // `exportedAt` is stamped at build time, so it necessarily differs
          // between two separate invocations; everything else must match.
          ..remove('exportedAt');
      }

      final bundle = await payloadFor('Share (program + dances)');
      final json = await payloadFor('Export as JSON file');

      // Guard the guard: a comparison of two empty-ish payloads would pass
      // whatever the code did, so assert the fixture really exercised every
      // entity list before comparing them.
      expect((bundle['programs']! as List), hasLength(1));
      expect((bundle['dances']! as List), hasLength(2));
      expect((bundle['choreographers']! as List), hasLength(1));
      expect((bundle['venues']! as List), hasLength(1));

      expect(json, equals(bundle));
    });
  });

  group('buildProgramPdf', () {
    testWidgets('produces a non-empty PDF document', (tester) async {
      final bytes = await buildProgramPdf(
        _program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
            ProgramSlot(id: 's3', position: 2, text: 'Waltz break'),
          ],
        ),
        titleFor: _titles,
      );

      expect(bytes, isNotEmpty);
      // A valid PDF begins with the "%PDF" magic header.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('handles an empty program', (tester) async {
      final bytes = await buildProgramPdf(
        _program(title: 'Empty Night'),
        titleFor: _titles,
      );
      expect(bytes, isNotEmpty);
    });

    testWidgets('renders a linked venue without throwing', (tester) async {
      final bytes = await buildProgramPdf(
        _program(
          venueId: 'v1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
        titleFor: _titles,
        venuesById: {'v1': _venue},
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('renders a linked venue with only a name (no detail fields)', (
      tester,
    ) async {
      final bytes = await buildProgramPdf(
        _program(venueId: 'v2'),
        titleFor: _titles,
        venuesById: {'v2': Venue(id: 'v2', name: 'Bare Hall')},
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('venueLocalityLine', () {
    test('joins city/state with a comma and the postal with a space', () {
      expect(venueLocalityLine(_venue), 'Montpelier, VT 05602-1234');
    });

    test('drops the state and postal when only a city is present', () {
      expect(
        venueLocalityLine(Venue(id: 'v', name: 'X', city: 'Montpelier')),
        'Montpelier',
      );
    });

    test('formats a bare ZIP with no +4', () {
      expect(
        venueLocalityLine(
          Venue(id: 'v', name: 'X', city: 'Montpelier', postalCode: '05602'),
        ),
        'Montpelier 05602',
      );
    });

    test('is empty when no locality parts are present', () {
      expect(venueLocalityLine(Venue(id: 'v', name: 'X')), isEmpty);
    });

    testWidgets('exports a program whose dance was purged, without corruption '
        '(#459 export coverage)', (tester) async {
      // End-to-end regression for the purge → export path (#429/#459): a
      // dance-only slot's dance is soft-deleted and then hard-purged by the
      // retention sweep, which tombstones the slot with the dance title. The
      // affected program must still render to PDF — the dance itself is gone,
      // so the exporter's title lookup misses it, yet the tombstone caption
      // carries the slot.
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(
          id: 'gone',
          title: 'Purged Reel',
          authorIds: const [],
          figures: const [],
          sourceCitations: const [],
          customFields: const [],
          createdAt: _now,
          updatedAt: _now,
          deletedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repos.programs.create(
        _program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'gone'),
            ProgramSlot(id: 's2', position: 1, text: 'Waltz break'),
          ],
        ),
      );

      await repos.dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      final purged = await repos.programs.getById('p1');
      expect(purged, isNotNull);
      // The tombstone survived and the dance is truly gone.
      expect(purged!.slots.first.danceId, isNull);
      expect(purged.slots.first.text, 'Purged Reel');

      // A real exporter's title lookup now misses the purged dance.
      final bytes = await buildProgramPdf(purged, titleFor: (_) => null);

      expect(bytes, isNotEmpty);
      // A valid PDF begins with the "%PDF" magic header.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  // ---------------------------------------------------------------------------
  // Figures-inclusion prompt (issue #853, asks 2 & 3)
  // ---------------------------------------------------------------------------
  // Guard: a dance fixture used here MUST have non-empty figures so the tests
  // are not vacuous. Each test asserts this individually before using it.
  final danceWithFigures = _dances['d1']!;

  group('figures-inclusion prompt', () {
    /// Builds a menu that has a danceFor resolver, so _hasFigures can fire.
    Widget figuresMenu({
      required Program program,
      required void Function(ShareParams) onShare,
      void Function()? onPdf,
    }) => MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        appBar: AppBar(
          actions: [
            ProgramExportMenu(
              program: program,
              titleFor: _titles,
              danceFor: _danceFor,
              shareInvoker: (params) async => onShare(params),
              pdfLayouter: ({required name, required onLayout}) async =>
                  onPdf?.call(),
            ),
          ],
        ),
      ),
    );

    testWidgets('prompt shown when program has dances with figures', (
      tester,
    ) async {
      // Mutation that would catch a regression: if the _hasFigures guard is
      // removed and the prompt is never shown, find.byKey returns nothing.
      assert(
        danceWithFigures.figures.isNotEmpty,
        'guard: fixture must have figures',
      );
      ShareParams? captured;
      await tester.pumpWidget(
        figuresMenu(
          program: _program(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          onShare: (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('program-figures-prompt-dialog')),
        findsOneWidget,
      );
      // Dialog is open — share not yet invoked.
      expect(captured, isNull);
    });

    testWidgets(
      'prompt NOT shown when no dances have figures → proceeds as set-list-only',
      (tester) async {
        // d2 has no figures. Mutation: if _hasFigures always returns true, the
        // dialog appears → share is not invoked → captured stays null → assertion
        // on captured being non-null fails.
        ShareParams? captured;
        await tester.pumpWidget(
          figuresMenu(
            program: _program(
              slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd2')],
            ),
            onShare: (p) => captured = p,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share set list (text)'));
        await tester.pumpAndSettle();

        // No dialog; share proceeds immediately.
        expect(
          find.byKey(const ValueKey('program-figures-prompt-dialog')),
          findsNothing,
        );
        expect(captured, isNotNull);
        // Output is set-list-only (no figure cards).
        expect(captured!.text, isNotNull);
        expect(captured!.text, contains('The Nice Combination'));
        expect(captured!.text, isNot(contains('---')));
      },
    );

    testWidgets('Cancel on prompt aborts the share — captured stays null', (
      tester,
    ) async {
      // Mutation: remove the null-check on _figuresConsent result → share
      // proceeds after cancel → captured becomes non-null → assertion fails.
      ShareParams? captured;
      await tester.pumpWidget(
        figuresMenu(
          program: _program(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          onShare: (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('program-figures-prompt-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    testWidgets('"Set list only" → share text has no figure cards', (
      tester,
    ) async {
      // Mutation: make "set list only" fall through to _plainTextWithFigures →
      // text contains "---" separator → assertion fails.
      assert(
        danceWithFigures.figures.isNotEmpty,
        'guard: fixture must have figures',
      );
      ShareParams? captured;
      await tester.pumpWidget(
        figuresMenu(
          program: _program(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          onShare: (p) => captured = p,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      // Confirm with default (set list only).
      await tester.tap(
        find.byKey(const ValueKey('program-figures-prompt-confirm')),
      );
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.text, contains('Rory O\'More'));
      // No separator that marks an appended dance card.
      expect(captured!.text, isNot(contains('---')));
    });

    testWidgets(
      '"Set list and figures" → share text includes figure card for dance with figures',
      (tester) async {
        // Mutation: remove the figures append in _plainTextWithFigures → "---"
        // separator absent → assertion fails.
        assert(
          danceWithFigures.figures.isNotEmpty,
          'guard: fixture must have figures',
        );
        ShareParams? captured;
        await tester.pumpWidget(
          figuresMenu(
            program: _program(
              slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
            ),
            onShare: (p) => captured = p,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share set list (text)'));
        await tester.pumpAndSettle();

        // Choose "Set list and figures".
        await tester.tap(
          find.byKey(
            const ValueKey('program-figures-prompt-set-list-and-figures'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('program-figures-prompt-confirm')),
        );
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.text, contains('Rory O\'More'));
        // Figure card separator and the dance title appear in the appendix.
        expect(captured!.text, contains('---'));
      },
    );

    testWidgets(
      'alternate dance labeled "Alternate" in set-list-and-figures share',
      (tester) async {
        // Mutation: remove the alternate label in _plainTextWithFigures →
        // "Alternate" absent from text → assertion fails.
        assert(
          danceWithFigures.figures.isNotEmpty,
          'guard: fixture must have figures',
        );
        // Use a note-only primary so d1 (with figures) appears as the alternate.
        ShareParams? captured;
        await tester.pumpWidget(
          figuresMenu(
            program: _program(
              slots: [
                ProgramSlot(id: 's1', position: 0, text: 'opener'),
                ProgramSlot(id: 's2', position: 1, danceId: 'd1', isAlt: true),
              ],
            ),
            onShare: (p) => captured = p,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share set list (text)'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey('program-figures-prompt-set-list-and-figures'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('program-figures-prompt-confirm')),
        );
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        // The alternate dance should be labelled in the appendix, and the title
        // must appear exactly once in the figure appendix — the mark is on the
        // separator line ("--- Alternate") and danceToPlainText emits the title.
        // Mutation that would catch a regression: removing the isAlternate check
        // causes the separator to be plain "---" and "Alternate" is absent.
        // The exact-once count in the appendix catches the double-title bug where
        // "Alternate: <title>" was printed before the card that also opens with
        // the title.
        expect(captured!.text, contains('Alternate'));
        final appendix = captured!.text!.split('---').last;
        final titleOccurrences = 'Rory O\'More'.allMatches(appendix).length;
        expect(
          titleOccurrences,
          1,
          reason:
              'alternate title must appear exactly once in the figure appendix',
        );
      },
    );

    testWidgets(
      'PDF path: "Set list and figures" → appendDances reaches the PDF builder',
      (tester) async {
        // The previous version of this test only checked that the pdfLayouter
        // spy was invoked — which stayed GREEN when appendDances was removed,
        // because the spy ignored its onLayout argument entirely. Found by a
        // deliberate mutation audit of merged code.
        //
        // This version captures the onLayout closure from both the "set list
        // and figures" path and the "set list only" path, calls each, and
        // compares their byte sizes. Both closures are built through _exportPdf
        // with identical parameters (same program, same formatDate, same
        // labels), so the comparison is a true differential: any size difference
        // comes from appendDances alone.
        //
        // A bare buildProgramPdf call was considered as the baseline but
        // rejected: _exportPdf passes formatDate and programExportLabels, so a
        // bare call and the export-path call produce different byte counts even
        // with no appendix — any size delta wouldn't be attributable to
        // appendDances. Using two closures from the same _exportPdf call
        // eliminates that ambiguity.
        //
        // Mutation that would catch a regression: remove appendDances from the
        // buildProgramPdf call in _exportPdf. Both closures then call
        // buildProgramPdf with identical arguments and produce identical bytes:
        //   Expected: a value greater than <N>   (measured ~8894 at time of writing)
        //   Actual: <N>   (both paths produce identical bytes)
        assert(
          danceWithFigures.figures.isNotEmpty,
          'guard: fixture must have figures',
        );
        final prog = _program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        );

        LayoutCallback? capturedWithFigures;
        LayoutCallback? capturedSetListOnly;

        final widget = MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: prog,
                  titleFor: _titles,
                  danceFor: _danceFor,
                  shareInvoker: (params) async {},
                  pdfLayouter: ({required name, required onLayout}) async {
                    // Called exactly twice: first tap → capturedWithFigures,
                    // second tap → capturedSetListOnly (order matches taps below).
                    // Fail loudly on a third call — a silent overwrite would let
                    // the test pass against the wrong closure, the same defect
                    // this PR exists to fix one level up.
                    if (capturedWithFigures == null) {
                      capturedWithFigures = onLayout;
                    } else if (capturedSetListOnly == null) {
                      capturedSetListOnly = onLayout;
                    } else {
                      fail(
                        'pdfLayouter called more than twice — unexpected invocation',
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();

        // ── First export: "Set list and figures" ──────────────────────────
        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export / print PDF'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('program-figures-prompt-dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(
            const ValueKey('program-figures-prompt-set-list-and-figures'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('program-figures-prompt-confirm')),
        );
        await tester.pumpAndSettle();

        // ── Second export: "Set list only" ────────────────────────────────
        await tester.tap(find.byKey(const ValueKey('program-export-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export / print PDF'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('program-figures-prompt-dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('program-figures-prompt-set-list-only')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('program-figures-prompt-confirm')),
        );
        await tester.pumpAndSettle();

        expect(capturedWithFigures, isNotNull);
        expect(capturedSetListOnly, isNotNull);

        final withFiguresBytes = await capturedWithFigures!(PdfPageFormat.a4);
        final setListOnlyBytes = await capturedSetListOnly!(PdfPageFormat.a4);

        // A PDF with a figure appendix is larger than the set-list-only PDF
        // built through the identical construction path. Proves appendDances
        // reached buildProgramPdf, but does not verify appendix contents —
        // any additional bytes satisfy it. For the guarded regression
        // (appendDances dropped entirely), the comparison discriminates
        // correctly.
        expect(
          withFiguresBytes.length,
          greaterThan(setListOnlyBytes.length),
          reason:
              'PDF with figures must be larger than set-list-only PDF; '
              'equal length means appendDances was silently dropped',
        );
      },
    );

    testWidgets('PDF path: Cancel on figures prompt → pdf layouter NOT invoked', (
      tester,
    ) async {
      // Mutation: remove null-check on _figuresConsent → PDF is invoked after
      // cancel → pdfInvoked flips to true → assertion fails.
      // Note: this test asserts on invocation, not content — that's correct
      // here because the question is "did cancel abort the export", not "what
      // did the PDF contain". Checked by mutation audit: goes RED when the
      // null-guard is removed. The content question is covered by the test above.
      var pdfInvoked = false;
      await tester.pumpWidget(
        figuresMenu(
          program: _program(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          onShare: (_) {},
          onPdf: () => pdfInvoked = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(pdfInvoked, isFalse);
    });
  });
}
