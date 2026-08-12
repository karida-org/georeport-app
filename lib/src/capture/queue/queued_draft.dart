import 'package:latlong2/latlong.dart';

import '../issue_draft.dart';

/// Where a queued draft is in its life. The order of states encodes the
/// exactly-once guarantee for issue creation:
///
/// - [pending]: safe to (re)try; the create request has never left the
///   device, or provably never reached the server.
/// - [creating]: a create request was sent and its outcome is unknown (the
///   app died, the response was lost). Before any retry the server must be
///   asked whether the issue already exists.
/// - [failed]: the server rejected the draft permanently; only the user can
///   fix or discard it.
enum QueuedDraftState { pending, creating, failed }

/// One photo of a queued draft: stored on disk under [storedName], uploaded
/// as [filename]. [token] is set as soon as its upload succeeded, so a
/// restart re-uploads only what is missing.
class QueuedPhoto {
  const QueuedPhoto({
    required this.storedName,
    required this.filename,
    this.contentType,
    this.token,
  });

  factory QueuedPhoto.fromJson(Map<String, dynamic> json) => QueuedPhoto(
    storedName: json['stored_name'] as String? ?? '',
    filename: json['filename'] as String? ?? 'photo.jpg',
    contentType: json['content_type'] as String?,
    token: json['token'] as String?,
  );

  final String storedName;
  final String filename;
  final String? contentType;
  final String? token;

  QueuedPhoto withToken(String? token) => QueuedPhoto(
    storedName: storedName,
    filename: filename,
    contentType: contentType,
    token: token,
  );

  Map<String, dynamic> toJson() => {
    'stored_name': storedName,
    'filename': filename,
    if (contentType != null) 'content_type': contentType,
    if (token != null) 'token': token,
  };
}

/// A draft parked in the outbox: everything [IssueDraft] carries except the
/// photo bytes (those live as files), plus the submission bookkeeping.
class QueuedDraft {
  const QueuedDraft({
    required this.id,
    required this.connectionId,
    required this.createdAt,
    required this.projectId,
    required this.trackerId,
    required this.subject,
    this.description = '',
    this.location,
    this.customFieldValues = const {},
    this.photos = const [],
    this.state = QueuedDraftState.pending,
    this.attempts = 0,
    this.tokenResets = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  factory QueuedDraft.fromJson(Map<String, dynamic> json) {
    final lat = json['lat'] as num?;
    final lon = json['lon'] as num?;
    final rawValues = json['custom_field_values'];
    return QueuedDraft(
      id: json['id'] as String? ?? '',
      connectionId: json['connection_id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      projectId: (json['project_id'] as num?)?.toInt() ?? 0,
      trackerId: (json['tracker_id'] as num?)?.toInt() ?? 0,
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: lat != null && lon != null
          ? LatLng(lat.toDouble(), lon.toDouble())
          : null,
      customFieldValues: rawValues is Map<String, dynamic>
          ? {
              for (final entry in rawValues.entries)
                if (int.tryParse(entry.key) case final int fieldId)
                  fieldId: entry.value is List
                      ? (entry.value as List).whereType<String>().toList()
                      : '${entry.value}',
            }
          : const {},
      photos: [
        for (final photo
            in (json['photos'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
          QueuedPhoto.fromJson(photo),
      ],
      state:
          QueuedDraftState.values.asNameMap()[json['state']] ??
          QueuedDraftState.pending,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      tokenResets: (json['token_resets'] as num?)?.toInt() ?? 0,
      nextAttemptAt: DateTime.tryParse(
        json['next_attempt_at'] as String? ?? '',
      )?.toUtc(),
      lastError: json['last_error'] as String?,
    );
  }

  final String id;
  final String connectionId;
  final DateTime createdAt;
  final int projectId;
  final int trackerId;
  final String subject;
  final String description;
  final LatLng? location;
  final Map<int, Object> customFieldValues;
  final List<QueuedPhoto> photos;
  final QueuedDraftState state;
  final int attempts;

  /// How often the attachment tokens were reset after a 422, so a server
  /// that keeps rejecting the uploads cannot loop forever.
  final int tokenResets;
  final DateTime? nextAttemptAt;
  final String? lastError;

  Map<String, dynamic> toJson() => {
    'id': id,
    'connection_id': connectionId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'project_id': projectId,
    'tracker_id': trackerId,
    'subject': subject,
    'description': description,
    if (location case final LatLng location) ...{
      'lat': location.latitude,
      'lon': location.longitude,
    },
    'custom_field_values': {
      for (final entry in customFieldValues.entries)
        '${entry.key}': entry.value,
    },
    'photos': [for (final photo in photos) photo.toJson()],
    'state': state.name,
    'attempts': attempts,
    'token_resets': tokenResets,
    if (nextAttemptAt case final DateTime at)
      'next_attempt_at': at.toUtc().toIso8601String(),
    if (lastError != null) 'last_error': lastError,
  };

  QueuedDraft copyWith({
    List<QueuedPhoto>? photos,
    QueuedDraftState? state,
    int? attempts,
    int? tokenResets,
    DateTime? nextAttemptAt,
    String? lastError,
    bool clearNextAttempt = false,
    bool clearError = false,
  }) => QueuedDraft(
    id: id,
    connectionId: connectionId,
    createdAt: createdAt,
    projectId: projectId,
    trackerId: trackerId,
    subject: subject,
    description: description,
    location: location,
    customFieldValues: customFieldValues,
    photos: photos ?? this.photos,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    tokenResets: tokenResets ?? this.tokenResets,
    nextAttemptAt: clearNextAttempt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  /// The `POST /issues.json` body, built through [IssueDraft] so queued and
  /// direct submissions can never drift apart.
  Map<String, dynamic> payload() {
    final draft = IssueDraft(
      projectId: projectId,
      trackerId: trackerId,
      subject: subject,
      description: description,
      location: location,
      customFieldValues: customFieldValues,
    );
    return draft.toPayload([
      for (final photo in photos)
        if (photo.token case final String token)
          {
            'token': token,
            'filename': photo.filename,
            if (photo.contentType case final String type) 'content_type': type,
          },
    ]);
  }
}
