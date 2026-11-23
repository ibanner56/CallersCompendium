import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/dance_code.dart';
import 'package:compendium_app/src/export/dance_share_bundle.dart';
import 'package:compendium_app/src/widgets/dance_code_view.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zxing2/qrcode.dart';

import 'support/fake_wakelock.dart';

/// Reads back what the Show code screen really draws (#2334): the screen is
/// rendered to pixels and a standard QR decoder (`zxing2`) reads them. The
/// plan's own data is never consulted, so this can only pass if a scanner
/// could read the screen: the quiet zone, whole-pixel modules, the light card
/// in a dark theme, and the brand mark over the middle.

String _seedBundle() {
  final read = decodeArchive(
    File('assets/seed/baby_rose.json').readAsStringSync(),
  );
  final people = {for (final c in read.archive.choreographers) c.id: c};
  return buildDanceShareBundle(
    read.archive.dances.single,
    choreographerFor: (id) => people[id],
    tagFor: (_) => null,
    publishedSourceFor: (_) => null,
    customFieldFor: (_) => null,
    now: DateTime.utc(2026, 11, 22),
  );
}

/// A pseudo-random link of exactly [length] characters, so a code fills a
/// version (a repeated character would compress nothing but also look like
/// nothing a scanner sees in a real dance).
DanceCodeShown _planOfLength(int length) {
  var state = 13579;
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final body = String.fromCharCodes([
    for (var i = 0; i < length - danceLinkPrefix.length; i++)
      alphabet.codeUnitAt(
        (() {
          state = (state * 1103515245 + 12345) & 0x7fffffff;
          return (state >> 8) % alphabet.length;
        })(),
      ),
  ]);
  return planDanceLink('$danceLinkPrefix$body') as DanceCodeShown;
}

class _Seen {
  _Seen(this.text, this.tilePixels, this.warmPixels);

  /// What a QR decoder read from the pixels, or null if it found nothing.
  final String? text;

  /// Pixels in the brand tile's dark navy (`BrandMark.brandBackground`), and
  /// in the warm oranges of the dancers: proof the mark's art really painted,
  /// not just its white clear zone.
  final int tilePixels;
  final int warmPixels;
}

Future<_Seen> _read(RenderRepaintBoundary boundary, double density) async {
  final image = await boundary.toImage(pixelRatio: density);
  final data = (await image.toByteData())!;
  final pixels = Int32List(image.width * image.height);
  var tile = 0;
  var warm = 0;
  for (var i = 0; i < pixels.length; i++) {
    final r = data.getUint8(i * 4);
    final g = data.getUint8(i * 4 + 1);
    final b = data.getUint8(i * 4 + 2);
    pixels[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    if ((r - 0x1E).abs() < 6 && (g - 0x2A).abs() < 6 && (b - 0x38).abs() < 6) {
      tile++;
    }
    if (r > 220 && g > 120 && g < 200 && b < 140) warm++;
  }
  final bitmap = BinaryBitmap(
    HybridBinarizer(RGBLuminanceSource(image.width, image.height, pixels)),
  );
  String? text;
  try {
    text = QRCodeReader().decode(bitmap).text;
  } catch (_) {
    text = null;
  }
  return _Seen(text, tile, warm);
}

Future<_Seen> _look(
  WidgetTester tester,
  DanceCodeShown plan, {
  double? markFraction,
  Brightness brightness = Brightness.light,
  Size logicalSize = const Size(800, 1200),
  double density = 1,
}) async {
  // The picture is taken at the screen's own density, so the decoder sees
  // exactly the device pixels the screen would paint.
  tester.view
    ..physicalSize = logicalSize * density
    ..devicePixelRatio = density;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DanceCodeScreen(
          plan: plan,
          title: 'The Baby Rose',
          markFraction: markFraction ?? kDanceCodeMarkFraction,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  // The mark is an SVG asset, read from the bundle on a real clock: look until
  // it has painted (when this plan carries one), up to a deadline.
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  _Seen? seen;
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    seen = await tester.runAsync(() => _read(boundary, density));
  } while (plan.withMark &&
      seen!.tilePixels < 5000 &&
      DateTime.now().isBefore(deadline));
  return seen!;
}

void main() {
  setUp(installFakeWakelock);

  final seed = planDanceCode(_seedBundle()) as DanceCodeShown;
  // The same dance held to a lower version: a lower level, no mark.
  final unbranded =
      planDanceCode(_seedBundle(), maxVersion: 30) as DanceCodeShown;

  testWidgets('a code without the mark reads back as its link (control)', (
    tester,
  ) async {
    expect(unbranded.withMark, isFalse);
    final seen = await _look(tester, unbranded);
    expect(seen.text, unbranded.link);
    expect(seen.tilePixels, 0, reason: 'no mark on a lower level');
    expect(seen.warmPixels, 0);
  });

  testWidgets('the real dance shows with the mark and still reads back', (
    tester,
  ) async {
    expect(seed.withMark, isTrue);
    final seen = await _look(tester, seed);
    expect(seen.text, seed.link);
    expect(seen.tilePixels, greaterThan(5000), reason: 'the mark painted');
    expect(seen.warmPixels, greaterThan(100));
    expect(decodeDanceLink(seen.text!), _seedBundle());
  });

  testWidgets('it reads back in a dark theme too: the card stays light', (
    tester,
  ) async {
    final seen = await _look(tester, seed, brightness: Brightness.dark);
    expect(seen.text, seed.link);
  });

  testWidgets('the densest code that carries the mark reads back', (
    tester,
  ) async {
    final densest = _planOfLength(DanceCodeLevel.high.byteCapacity);
    expect(densest.withMark, isTrue);
    expect(densest.version, 40);
    final seen = await _look(tester, densest);
    expect(seen.text, densest.link);
    expect(seen.tilePixels, greaterThan(5000));
  });

  testWidgets('it reads back on a 2.625x phone screen too', (tester) async {
    // Not every screen is 1x or 3x: modules are whole device pixels at this
    // density as well.
    final seen = await _look(
      tester,
      seed,
      logicalSize: const Size(412, 915),
      density: 2.625,
    );
    expect(seen.text, seed.link);
    expect(seen.tilePixels, greaterThan(5000));
  });

  testWidgets('the mark has room to spare: a much larger one still reads', (
    tester,
  ) async {
    // The shipped size is 18%; a mark at 30% still decodes. A decoder is not
    // a phone camera, so this is margin in a software reader, not a promise.
    final seen = await _look(tester, seed, markFraction: 0.30);
    expect(seen.text, seed.link);
  });

  testWidgets('a mark enlarged past what the code can lose is not read', (
    tester,
  ) async {
    // Shows this test can fail: the same code with the mark at 45% of its
    // width has lost too much to be decoded.
    final seen = await _look(tester, seed, markFraction: 0.45);
    expect(seen.text, isNull);
  });
}
