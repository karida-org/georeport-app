import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Byte-size cap above which photos are recompressed before upload.
/// Overridable at build time: --dart-define=GEOREPORT_UPLOAD_MAX_KB=3000
const uploadMaxKb = int.fromEnvironment(
  'GEOREPORT_UPLOAD_MAX_KB',
  defaultValue: 1536,
);

/// Longest edge after downscaling; smaller images are never enlarged.
const uploadMaxDimension = int.fromEnvironment(
  'GEOREPORT_UPLOAD_MAX_DIMENSION',
  defaultValue: 2048,
);

/// A function shrinking photo bytes for upload; injectable so the queue's
/// state machine can be tested without the native compression plugin.
typedef ImageShrinker =
    Future<Uint8List> Function(Uint8List bytes, String? contentType);

/// Downscales and recompresses a JPEG above the size cap, keeping EXIF
/// (the GPS position must survive). Non-JPEG input passes through untouched:
/// recompressing would change the format out from under the declared
/// filename and content type. Any failure falls back to the original bytes;
/// an oversized upload beats a lost report.
Future<Uint8List> shrinkForUpload(Uint8List bytes, String? contentType) async {
  final type = contentType?.split(';').first.trim().toLowerCase();
  if (bytes.lengthInBytes <= uploadMaxKb * 1024 ||
      (type != 'image/jpeg' && type != 'image/jpg')) {
    return bytes;
  }
  try {
    final shrunk = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: uploadMaxDimension,
      minHeight: uploadMaxDimension,
      quality: 85,
      keepExif: true,
    );
    return shrunk.lengthInBytes < bytes.lengthInBytes ? shrunk : bytes;
  } on Exception {
    return bytes;
  }
}
