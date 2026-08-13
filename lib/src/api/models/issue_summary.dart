/// The lean issue shape used in bundle feature properties and unplaced lists.
///
/// Every key is present in the payload, with explicit nulls for unset values.
/// Note the contract quirk: `status_id` and `tracker_id` are ids, while
/// priority, assignee, category, and version arrive as display names.
class IssueSummary {
  const IssueSummary({
    required this.id,
    required this.projectId,
    required this.subject,
    required this.statusId,
    required this.trackerId,
    required this.doneRatio,
    required this.lockVersion,
    required this.editable,
    this.priority,
    this.assignedTo,
    this.assignedToId,
    this.category,
    this.fixedVersion,
    this.startDate,
    this.dueDate,
    this.estimatedHours,
    this.createdOn,
    this.updatedOn,
    this.raw = const {},
  });

  factory IssueSummary.fromJson(Map<String, dynamic> json) {
    return IssueSummary(
      raw: json,
      id: (json['id'] as num).toInt(),
      projectId: (json['project_id'] as num).toInt(),
      subject: json['subject'] as String? ?? '',
      statusId: (json['status_id'] as num).toInt(),
      trackerId: (json['tracker_id'] as num).toInt(),
      doneRatio: (json['done_ratio'] as num?)?.toInt() ?? 0,
      lockVersion: (json['lock_version'] as num?)?.toInt() ?? 0,
      editable: json['editable'] == true,
      priority: json['priority'] as String?,
      assignedTo: json['assigned_to'] as String?,
      assignedToId: (json['assigned_to_id'] as num?)?.toInt(),
      category: json['category'] as String?,
      fixedVersion: json['fixed_version'] as String?,
      startDate: _date(json['start_date']),
      dueDate: _date(json['due_date']),
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble(),
      createdOn: _date(json['created_on']),
      updatedOn: _date(json['updated_on']),
    );
  }

  final int id;
  final int projectId;
  final String subject;
  final int statusId;
  final int trackerId;
  final int doneRatio;
  final int lockVersion;
  final bool editable;
  final String? priority;
  final String? assignedTo;

  /// The assignee's user id. Prefer this over [assignedTo] whenever the
  /// question is "who is this", because [assignedTo] is rendered through the
  /// instance's `user_format` setting and is only a label. Null on servers
  /// older than the field, where a name comparison is the only option left.
  final int? assignedToId;
  final String? category;
  final String? fixedVersion;
  final DateTime? startDate;
  final DateTime? dueDate;
  final double? estimatedHours;
  final DateTime? createdOn;
  final DateTime? updatedOn;

  /// The payload this summary was parsed from, kept verbatim so the offline
  /// cache can persist exactly what the server sent (re-parsed on load; no
  /// hand-written serialization to drift out of sync with the contract).
  final Map<String, dynamic> raw;
}

DateTime? _date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;
