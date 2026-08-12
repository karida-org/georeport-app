import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// One photo attached to a draft, kept as raw bytes until submission.
class DraftPhoto {
  const DraftPhoto({
    required this.filename,
    required this.bytes,
    this.contentType,
  });

  final String filename;
  final Uint8List bytes;

  /// MIME type when known; omitted from the upload otherwise.
  final String? contentType;
}

/// Everything a new issue needs, independent of any widget state, so
/// submission logic is a pure transformation that can be tested and later
/// queued for offline retry.
class IssueDraft {
  const IssueDraft({
    required this.projectId,
    required this.trackerId,
    required this.subject,
    this.description = '',
    this.location,
    this.photos = const [],
    this.customFieldValues = const {},
  });

  final int projectId;
  final int trackerId;
  final String subject;
  final String description;
  final LatLng? location;
  final List<DraftPhoto> photos;

  /// Field id to value; a list value for multi-value fields.
  final Map<int, Object> customFieldValues;

  /// The `POST /issues.json` body, with uploaded attachment tokens.
  /// Geometry rides the redmine_gtt `geojson` safe attribute.
  Map<String, dynamic> toPayload(List<Map<String, String>> uploads) {
    final location = this.location;
    return {
      'issue': {
        'project_id': projectId,
        'tracker_id': trackerId,
        'subject': subject,
        if (description.isNotEmpty) 'description': description,
        if (location != null)
          'geojson':
              '{"type":"Feature","geometry":{"type":"Point",'
              '"coordinates":[${location.longitude},${location.latitude}]},'
              '"properties":{}}',
        if (customFieldValues.isNotEmpty)
          'custom_fields': [
            for (final entry in customFieldValues.entries)
              {'id': entry.key, 'value': entry.value},
          ],
        if (uploads.isNotEmpty) 'uploads': uploads,
      },
    };
  }
}
