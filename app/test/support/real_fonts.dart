import 'dart:io';

import 'package:flutter/services.dart';

/// Registers the bundled font files under the family names the theme uses, so
/// a widget test measures text with real glyph widths.
///
/// The default Ahem test font draws every glyph as a full-em box, which
/// roughly doubles some overflows and hides others (it misled an earlier
/// dance-editor fix). Any test that asserts "this fits" at a given width or text
/// scale needs the real fonts. Call it before pumping; run from the `app`
/// directory, which `flutter test` does.
Future<void> loadBundledFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }

  await load('AtkinsonHyperlegible', [
    'AtkinsonHyperlegible-Regular.ttf',
    'AtkinsonHyperlegible-Bold.ttf',
  ]);
  await load('Roboto', ['Roboto-VariableFont.ttf']);
  await load('Fraunces', ['Fraunces-VariableFont.ttf']);
}
