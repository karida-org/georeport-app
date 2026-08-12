/// Parsed `GET /gtt_sync/projects/:id/schema`: what a permission-aware
/// create/edit form may offer for the current user in one project.
class ProjectSchema {
  const ProjectSchema({
    required this.trackers,
    required this.customFields,
    required this.writable,
  });

  factory ProjectSchema.fromJson(Map<String, dynamic> json) {
    return ProjectSchema(
      trackers: [
        for (final tracker in json['trackers'] as List<dynamic>? ?? const [])
          if (tracker is Map<String, dynamic>)
            SchemaTracker(
              id: (tracker['id'] as num?)?.toInt() ?? 0,
              name: tracker['name'] as String? ?? '',
            ),
      ],
      customFields: [
        for (final field in json['custom_fields'] as List<dynamic>? ?? const [])
          if (field is Map<String, dynamic>) SchemaCustomField.fromJson(field),
      ],
      writable: (json['writable'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  final List<SchemaTracker> trackers;
  final List<SchemaCustomField> customFields;
  final Set<String> writable;

  /// The custom fields applicable to one tracker, required ones first.
  List<SchemaCustomField> fieldsForTracker(int trackerId) {
    final applicable = [
      for (final field in customFields)
        if (field.trackerIds.isEmpty || field.trackerIds.contains(trackerId))
          field,
    ];
    applicable.sort((a, b) {
      if (a.required != b.required) {
        return a.required ? -1 : 1;
      }
      return a.id.compareTo(b.id);
    });
    return applicable;
  }
}

class SchemaTracker {
  const SchemaTracker({required this.id, required this.name});

  final int id;
  final String name;
}

class SchemaCustomField {
  const SchemaCustomField({
    required this.id,
    required this.name,
    required this.fieldFormat,
    required this.required,
    required this.multiple,
    required this.possibleValues,
    required this.trackerIds,
  });

  factory SchemaCustomField.fromJson(Map<String, dynamic> json) {
    return SchemaCustomField(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      fieldFormat: json['field_format'] as String? ?? 'string',
      required: json['required'] == true,
      multiple: json['multiple'] == true,
      possibleValues: (json['possible_values'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      trackerIds: (json['tracker_ids'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((id) => id.toInt())
          .toList(),
    );
  }

  final int id;
  final String name;
  final String fieldFormat;
  final bool required;
  final bool multiple;
  final List<String> possibleValues;
  final List<int> trackerIds;
}
