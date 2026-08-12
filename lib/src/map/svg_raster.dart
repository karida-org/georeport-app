import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Rasterizes an SVG string (for example a GTT tracker icon) into PNG bytes,
/// suitable for registering as a map style image.
///
/// GTT tracker icons carry no fill of their own; [color] tints them.
Future<Uint8List> rasterizeSvg(
  String svg, {
  int size = 48,
  Color color = const Color(0xFF00695C),
}) async {
  final pictureInfo = await vg.loadPicture(
    SvgStringLoader(svg, theme: SvgTheme(currentColor: color)),
    null,
  );
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final scale = size / pictureInfo.size.width;
    canvas.scale(scale, size / pictureInfo.size.height);
    canvas.saveLayer(
      null,
      Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    );
    canvas.drawPicture(pictureInfo.picture);
    canvas.restore();
    final image = await recorder.endRecording().toImage(size, size);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    pictureInfo.picture.dispose();
  }
}
