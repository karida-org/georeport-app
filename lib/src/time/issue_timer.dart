/// One per-issue timer. Purely client-side: Redmine entries are hours, so a
/// timer is just accumulated duration waiting to become a quick log.
///
/// The one-running rule lives in the notifier; the model only knows whether
/// it is running ([runningSince] set) or paused.
class IssueTimer {
  const IssueTimer({
    required this.issueId,
    required this.projectId,
    required this.subject,
    required this.startedAt,
    this.accumulated = Duration.zero,
    this.runningSince,
  });

  factory IssueTimer.fromJson(Map<String, dynamic> json) => IssueTimer(
    issueId: (json['issue_id'] as num?)?.toInt() ?? 0,
    projectId: (json['project_id'] as num?)?.toInt() ?? 0,
    subject: json['subject'] as String? ?? '',
    startedAt:
        DateTime.tryParse(json['started_at'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    accumulated: Duration(
      seconds: (json['accumulated_s'] as num?)?.toInt() ?? 0,
    ),
    runningSince: DateTime.tryParse(
      json['running_since'] as String? ?? '',
    )?.toUtc(),
  );

  final int issueId;
  final int projectId;
  final String subject;

  /// When this timer was first started; the quick log's spent_on default.
  final DateTime startedAt;

  /// Time collected across previous running stretches.
  final Duration accumulated;

  /// Start of the current running stretch, null while paused.
  final DateTime? runningSince;

  bool get isRunning => runningSince != null;

  /// Total tracked time as of [now].
  Duration elapsed(DateTime now) {
    final since = runningSince;
    if (since == null) {
      return accumulated;
    }
    final stretch = now.difference(since);
    return accumulated + (stretch.isNegative ? Duration.zero : stretch);
  }

  IssueTimer copyWith({
    Duration? accumulated,
    DateTime? runningSince,
    bool clearRunning = false,
  }) => IssueTimer(
    issueId: issueId,
    projectId: projectId,
    subject: subject,
    startedAt: startedAt,
    accumulated: accumulated ?? this.accumulated,
    runningSince: clearRunning ? null : (runningSince ?? this.runningSince),
  );

  Map<String, dynamic> toJson() => {
    'issue_id': issueId,
    'project_id': projectId,
    'subject': subject,
    'started_at': startedAt.toUtc().toIso8601String(),
    'accumulated_s': accumulated.inSeconds,
    if (runningSince case final DateTime since)
      'running_since': since.toUtc().toIso8601String(),
  };
}
