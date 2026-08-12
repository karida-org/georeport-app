import 'issue_document.dart';

/// One time entry as the contract serves it.
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.hours,
    required this.spentOn,
    this.comments = '',
    this.activity,
    this.project,
    this.issue,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    NamedRef? ref(Object? value) =>
        value is Map<String, dynamic> ? NamedRef.fromJson(value) : null;
    return TimeEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      hours: (json['hours'] as num?)?.toDouble() ?? 0,
      spentOn: DateTime.tryParse(json['spent_on'] as String? ?? ''),
      comments: json['comments'] as String? ?? '',
      activity: ref(json['activity']),
      project: ref(json['project']),
      issue: json['issue'] is Map<String, dynamic>
          ? IssueRef.fromJson(json['issue'] as Map<String, dynamic>)
          : null,
    );
  }

  final int id;
  final double hours;
  final DateTime? spentOn;
  final String comments;
  final NamedRef? activity;
  final NamedRef? project;
  final IssueRef? issue;
}

/// The issue a time entry belongs to, as the index serves it.
class IssueRef {
  const IssueRef({required this.id, required this.subject});

  factory IssueRef.fromJson(Map<String, dynamic> json) => IssueRef(
    id: (json['id'] as num?)?.toInt() ?? 0,
    subject: json['subject'] as String? ?? '',
  );

  final int id;
  final String subject;
}

/// The own-entries index: a capped list plus totals computed over the whole
/// filtered range, so the summary stays correct even when the list is cut.
class TimeEntriesPage {
  const TimeEntriesPage({
    required this.entries,
    required this.totalHours,
    required this.totalCount,
  });

  factory TimeEntriesPage.fromJson(Map<String, dynamic> json) {
    return TimeEntriesPage(
      entries: [
        for (final entry in json['time_entries'] as List<dynamic>? ?? const [])
          if (entry is Map<String, dynamic>) TimeEntry.fromJson(entry),
      ],
      totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    );
  }

  final List<TimeEntry> entries;
  final double totalHours;
  final int totalCount;
}
