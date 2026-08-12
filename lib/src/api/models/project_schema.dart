/// Parsed `GET /gtt_sync/projects/:id/schema`: what a permission-aware
/// create/edit form may offer for the current user in one project.
/// One selectable option of a reference field (assignee, priority,
/// category, version): Redmine expects the numeric id, people read the name.
class SchemaOption {
  const SchemaOption({required this.id, required this.name});

  final int id;
  final String name;
}

/// The schema's reference options, narrowed rather than cast: an unexpected
/// shape yields no options (the picker hides) instead of throwing during
/// parse. Entries without a usable id and name are dropped, since neither
/// a nameless option nor one Redmine cannot resolve is selectable.
Map<String, List<SchemaOption>> _references(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    return const {};
  }
  final references = <String, List<SchemaOption>>{};
  for (final entry in raw.entries) {
    final options = <SchemaOption>[];
    for (final option in entry.value is List ? entry.value as List : const []) {
      if (option is! Map<String, dynamic>) {
        continue;
      }
      final id = (option['id'] as num?)?.toInt() ?? 0;
      final name = option['name'] as String? ?? '';
      if (id > 0 && name.isNotEmpty) {
        options.add(SchemaOption(id: id, name: name));
      }
    }
    references[entry.key] = options;
  }
  return references;
}

class ProjectSchema {
  const ProjectSchema({
    required this.trackers,
    required this.customFields,
    required this.writable,
    this.references = const {},
    this.timeEntry = const TimeEntrySection(),
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
      references: _references(json['references']),
      timeEntry: json['time_entry'] is Map<String, dynamic>
          ? TimeEntrySection.fromJson(
              json['time_entry'] as Map<String, dynamic>,
            )
          : const TimeEntrySection(),
    );
  }

  final List<SchemaTracker> trackers;
  final List<SchemaCustomField> customFields;
  final Set<String> writable;

  /// Selectable options per reference field (`assigned_to_id`,
  /// `priority_id`, `category_id`, `fixed_version_id`), served by the
  /// schema so pickers never guess ids.
  final Map<String, List<SchemaOption>> references;

  /// Whether and how the user may log time in this project; absent on
  /// servers without the time-entry contract.
  final TimeEntrySection timeEntry;

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

/// The schema's `time_entry` section: the permission, the project's
/// activities, and the attribute names a create may carry.
class TimeEntrySection {
  const TimeEntrySection({this.canLogTime = false, this.activities = const []});

  factory TimeEntrySection.fromJson(Map<String, dynamic> json) {
    return TimeEntrySection(
      canLogTime: json['can_log_time'] == true,
      activities: [
        for (final activity in json['activities'] as List<dynamic>? ?? const [])
          if (activity is Map<String, dynamic>)
            TimeEntryActivity(
              id: (activity['id'] as num?)?.toInt() ?? 0,
              name: activity['name'] as String? ?? '',
              isDefault: activity['is_default'] == true,
            ),
      ],
    );
  }

  final bool canLogTime;
  final List<TimeEntryActivity> activities;

  /// The activity a form preselects: the project default, else the first.
  TimeEntryActivity? get defaultActivity => activities.isEmpty
      ? null
      : activities.firstWhere(
          (a) => a.isDefault,
          orElse: () => activities.first,
        );
}

/// One time-entry activity available in a project.
class TimeEntryActivity {
  const TimeEntryActivity({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  final int id;
  final String name;
  final bool isDefault;
}
