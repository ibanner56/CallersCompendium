import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:zxing2/qrcode.dart';

/// Encoded pictures of QR codes, for the dance-code scanner's tests (#2336).
/// Drawn with dart:ui, so call them inside `tester.runAsync` in a widget
/// test.

/// A PNG of a QR code holding [text]: [module] pixels a module, a quiet zone
/// of four modules, set on a [canvas]-sized picture at [offset] (top left).
/// [inverted] draws it light on dark.
Future<Uint8List> qrPicture(
  String text, {
  int module = 4,
  ui.Size? canvas,
  ui.Offset offset = ui.Offset.zero,
  bool inverted = false,
}) async {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.l).matrix!;
  final side = (matrix.width + 8) * module;
  final size = canvas ?? ui.Size(side.toDouble(), side.toDouble());
  final light = ui.Paint()
    ..color = inverted
        ? const ui.Color(0xFF000000)
        : const ui.Color(0xFFFFFFFF);
  final dark = ui.Paint()
    ..color = inverted
        ? const ui.Color(0xFFFFFFFF)
        : const ui.Color(0xFF000000);
  final recorder = ui.PictureRecorder();
  final c = ui.Canvas(recorder)..drawRect(ui.Offset.zero & size, light);
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) == 1) {
        c.drawRect(
          ui.Rect.fromLTWH(
            offset.dx + (x + 4) * module,
            offset.dy + (y + 4) * module,
            module.toDouble(),
            module.toDouble(),
          ),
          dark,
        );
      }
    }
  }
  return _png(recorder, size);
}

/// A PNG of [size] with nothing on it but a grey square.
Future<Uint8List> blankPicture({ui.Size size = const ui.Size(400, 300)}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    )
    ..drawRect(
      const ui.Rect.fromLTWH(50, 50, 120, 120),
      ui.Paint()..color = const ui.Color(0xFF808080),
    );
  return _png(recorder, size);
}

Future<Uint8List> _png(ui.PictureRecorder recorder, ui.Size size) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
