import 'geojson.dart';

/// A `{@id, id, name}` reference from the issue document.
class NamedRef {
  const NamedRef({required this.id, required this.name});

  factory NamedRef.fromJson(Map<String, dynamic> json) {
    return NamedRef(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
    );
  }

  final int id;
  final String name;
}

/// One property change inside a journal entry. Description edits carry a
/// diff URL instead of inline values; labels are present when the server
/// resolved a reference id to a display name.
class JournalDetail {
  const JournalDetail({
    required this.name,
    this.oldValue,
    this.newValue,
    this.diffUrl,
  });

  factory JournalDetail.fromJson(Map<String, dynamic> json) {
    return JournalDetail(
      name: json['name'] as String? ?? '',
      oldValue: _displayString(json['old_label'] ?? json['old_value']),
      newValue: _displayString(json['new_label'] ?? json['new_value']),
      diffUrl: json['diff_url'] as String?,
    );
  }

  final String name;
  final String? oldValue;
  final String? newValue;
  final String? diffUrl;
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.isPrivate,
    required this.details,
    this.userName,
    this.createdOn,
    this.notes,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return JournalEntry(
      id: (json['id'] as num).toInt(),
      isPrivate: json['private_notes'] == true,
      details: [
        for (final detail in json['details'] as List<dynamic>? ?? const [])
          if (detail is Map<String, dynamic>) JournalDetail.fromJson(detail),
      ],
      userName: user?['name'] as String?,
      createdOn: _dateTime(json['created_on']),
      notes: json['notes'] as String?,
    );
  }

  final int id;
  final bool isPrivate;
  final List<JournalDetail> details;
  final String? userName;
  final DateTime? createdOn;
  final String? notes;
}

/// A custom field value in its detailed document form.
class CustomFieldValue {
  const CustomFieldValue({
    required this.id,
    required this.name,
    required this.values,
  });

  factory CustomFieldValue.fromJson(Map<String, dynamic> json) {
    final raw = json['value'];
    // Values arrive as strings for most formats, but numeric, bool, and
    // similar formats may serialize natively; anything non-null displays.
    final values = switch (raw) {
      final List<dynamic> list => [
        for (final item in list)
          if (_displayString(item) case final String value) value,
      ],
      _ => [if (_displayString(raw) case final String value) value],
    };
    return CustomFieldValue(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      values: values,
    );
  }

  final int id;
  final String name;
  final List<String> values;
}

class AttachmentInfo {
  const AttachmentInfo({
    required this.id,
    required this.filename,
    required this.isImage,
    required this.url,
    this.filesize,
    this.contentType,
    this.thumbnailUrl,
  });

  factory AttachmentInfo.fromJson(Map<String, dynamic> json) {
    return AttachmentInfo(
      id: (json['id'] as num).toInt(),
      filename: json['filename'] as String? ?? '',
      isImage: json['is_image'] == true,
      url: json['url'] as String? ?? '',
      filesize: (json['filesize'] as num?)?.toInt(),
      contentType: json['content_type'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }

  final int id;
  final String filename;
  final bool isImage;
  final String url;
  final int? filesize;
  final String? contentType;
  final String? thumbnailUrl;
}

/// The per-user editing contract: what this user may change on this issue.
class EditingContract {
  const EditingContract({
    required this.fields,
    required this.canDelete,
    required this.canAddNotes,
    required this.canAddAttachments,
    this.canLogTime = false,
    required this.statusTransitions,
  });

  factory EditingContract.fromJson(Map<String, dynamic> json) {
    return EditingContract(
      fields: (json['fields'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
      canDelete: json['can_delete'] == true,
      canAddNotes: json['can_add_notes'] == true,
      canAddAttachments: json['can_add_attachments'] == true,
      canLogTime: json['can_log_time'] == true,
      statusTransitions: [
        for (final status
            in json['status_transitions'] as List<dynamic>? ?? const [])
          NamedRef.fromJson(status as Map<String, dynamic>),
      ],
    );
  }

  final Set<String> fields;
  final bool canDelete;
  final bool canAddNotes;
  final bool canAddAttachments;

  /// Whether this user may log time on this issue (server-side:
  /// `Issue#time_loggable?`, i.e. `:log_time` plus the closed-issues rule).
  final bool canLogTime;
  final List<NamedRef> statusTransitions;
}

/// Parsed `GET /gtt_sync/issues/:id` JSON-LD document.
///
/// The server compacts null values away, so unset keys are absent rather
/// than null. The numeric issue id arrives under `identifier`.
class IssueDocument {
  const IssueDocument({
    required this.id,
    required this.iri,
    required this.subject,
    required this.status,
    required this.tracker,
    required this.project,
    required this.doneRatio,
    required this.isPrivate,
    required this.lockVersion,
    required this.journals,
    required this.attachments,
    required this.customFields,
    required this.editable,
    this.description,
    this.priority,
    this.author,
    this.assignedTo,
    this.startDate,
    this.dueDate,
    this.geometry,
    this.geometryJson,
    this.createdOn,
    this.updatedOn,
    this.closedOn,
  });

  factory IssueDocument.fromJson(Map<String, dynamic> json) {
    return IssueDocument(
      id: (json['identifier'] as num).toInt(),
      iri: json['@id'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      status: _ref(json['status'])!,
      tracker: _ref(json['tracker'])!,
      project: _ref(json['project'])!,
      doneRatio: (json['done_ratio'] as num?)?.toInt() ?? 0,
      isPrivate: json['is_private'] == true,
      lockVersion: (json['lock_version'] as num?)?.toInt() ?? 0,
      journals: [
        for (final journal in json['journals'] as List<dynamic>? ?? const [])
          JournalEntry.fromJson(journal as Map<String, dynamic>),
      ],
      attachments: [
        for (final attachment
            in json['attachments'] as List<dynamic>? ?? const [])
          AttachmentInfo.fromJson(attachment as Map<String, dynamic>),
      ],
      customFields: [
        for (final field in json['custom_fields'] as List<dynamic>? ?? const [])
          if (field is Map<String, dynamic>) CustomFieldValue.fromJson(field),
      ],
      editable: EditingContract.fromJson(
        json['editable'] as Map<String, dynamic>? ?? const {},
      ),
      description: json['description'] as String?,
      priority: _ref(json['priority']),
      author: _ref(json['author']),
      assignedTo: _ref(json['assigned_to']),
      startDate: _dateTime(json['start_date']),
      dueDate: _dateTime(json['due_date']),
      geometry: IssueGeometry.fromJson(
        json['geometry'] as Map<String, dynamic>?,
      ),
      geometryJson: json['geometry'] as Map<String, dynamic>?,
      createdOn: _dateTime(json['created_on']),
      updatedOn: _dateTime(json['updated_on']),
      closedOn: _dateTime(json['closed_on']),
    );
  }

  final int id;
  final String iri;
  final String subject;
  final NamedRef status;
  final NamedRef tracker;
  final NamedRef project;
  final int doneRatio;
  final bool isPrivate;
  final int lockVersion;
  final List<JournalEntry> journals;
  final List<AttachmentInfo> attachments;
  final List<CustomFieldValue> customFields;
  final EditingContract editable;
  final String? description;
  final NamedRef? priority;
  final NamedRef? author;
  final NamedRef? assignedTo;
  final DateTime? startDate;
  final DateTime? dueDate;
  final IssueGeometry? geometry;

  /// The untouched GeoJSON geometry, for handing to a map source.
  final Map<String, dynamic>? geometryJson;

  final DateTime? createdOn;
  final DateTime? updatedOn;
  final DateTime? closedOn;
}

NamedRef? _ref(Object? raw) =>
    raw is Map<String, dynamic> ? NamedRef.fromJson(raw) : null;

/// A scalar rendered for display: strings pass through, numbers and bools
/// stringify, everything else (null, nested structures) becomes null.
String? _displayString(Object? raw) {
  return switch (raw) {
    final String value when value.isNotEmpty => value,
    final num value => '$value',
    final bool value => '$value',
    _ => null,
  };
}

DateTime? _dateTime(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;
