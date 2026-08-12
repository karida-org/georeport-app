/// MIME types by photo file extension; unknown extensions yield null and
/// the upload simply carries no content type.
const _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

String? mimeForFilename(String filename) {
  final extension = filename.split('.').last.toLowerCase();
  return _mimeByExtension[extension];
}
