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

/// The pale floor of the raised brand mark's badge (`FLOOR` in
/// `tools/brand/generate_raised_mark.py`).
const _floor = (0xE5, 0xE8, 0xEE);

class _Seen {
  _Seen(this.text, this.floorPixels, this.artPixels);

  /// What a QR decoder read from the pixels, or null if it found nothing.
  final String? text;

  /// Pixels in the badge's floor tone: proof the badge painted.
  final int floorPixels;

  /// Pixels in the badge's middle that are clearly not floor: the raised
  /// mark's lit edges, lower edges and shadows. Proof the artwork is there,
  /// not just its floor.
  final int artPixels;
}

Future<_Seen> _read(
  RenderRepaintBoundary boundary,
  double density,
  Rect? badge,
) async {
  final image = await boundary.toImage(pixelRatio: density);
  final data = (await image.toByteData())!;
  final pixels = Int32List(image.width * image.height);
  // The badge in device pixels, and its middle (the rim shading is left out).
  final whole = badge == null
      ? Rect.zero
      : Rect.fromLTRB(
          badge.left * density,
          badge.top * density,
          badge.right * density,
          badge.bottom * density,
        );
  final middle = whole.deflate(whole.shortestSide * 0.2);
  var floor = 0;
  var art = 0;
  for (var i = 0; i < pixels.length; i++) {
    final r = data.getUint8(i * 4);
    final g = data.getUint8(i * 4 + 1);
    final b = data.getUint8(i * 4 + 2);
    pixels[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    if (badge == null) continue;
    final x = (i % image.width).toDouble();
    final y = (i ~/ image.width).toDouble();
    final off = [
      (r - _floor.$1).abs(),
      (g - _floor.$2).abs(),
      (b - _floor.$3).abs(),
    ].reduce((a, b) => a > b ? a : b);
    if (whole.contains(Offset(x, y)) && off <= 3) floor++;
    if (middle.contains(Offset(x, y)) && off >= 8) art++;
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
  return _Seen(text, floor, art);
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
  // The badge is an image asset, read from the bundle on a real clock: look
  // until it has painted (when this plan carries one), up to a deadline.
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  final badgeFinder = find.byKey(const ValueKey('dance-code-mark'));
  _Seen? seen;
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final badge = tester.any(badgeFinder) ? tester.getRect(badgeFinder) : null;
    seen = await tester.runAsync(() => _read(boundary, density, badge));
  } while (plan.withMark &&
      seen!.floorPixels < 1000 &&
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
    expect(seen.floorPixels, 0, reason: 'no badge on a lower level');
    expect(seen.artPixels, 0);
  });

  testWidgets('the real dance shows with the mark and still reads back', (
    tester,
  ) async {
    expect(seed.withMark, isTrue);
    final seen = await _look(tester, seed);
    expect(seen.text, seed.link);
    expect(seen.floorPixels, greaterThan(5000), reason: 'the badge painted');
    expect(
      seen.artPixels,
      greaterThan(1000),
      reason: 'the raised mark painted',
    );
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
    expect(seen.floorPixels, greaterThan(5000));
    expect(seen.artPixels, greaterThan(1000));
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
    expect(seen.floorPixels, greaterThan(5000));
    expect(seen.artPixels, greaterThan(1000));
  });

  testWidgets('the mark has room to spare: a much larger one still reads', (
    tester,
  ) async {
    // The shipped clear zone is 20% of the code's width; at 35% it still
    // decodes. A decoder is not a phone camera, so this is margin in a
    // software reader, not a promise.
    final seen = await _look(tester, seed, markFraction: 0.35);
    expect(seen.text, seed.link);
  });

  testWidgets('a mark enlarged past what the code can lose is not read', (
    tester,
  ) async {
    // Shows this test can fail: the same code with the clear zone at 55% of
    // its width has lost too much to be decoded.
    final seen = await _look(tester, seed, markFraction: 0.55);
    expect(seen.text, isNull);
  });
}
