import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/bundle.dart';
import '../../connections/connection_manager.dart';
import '../issues/issues_store.dart';

/// The worker's plate for today: assigned issues due today or overdue,
/// ordered by due date. This selection is the MVP ordering source; the
/// design keeps it pluggable so a server-computed schedule (route-ordered
/// task list) can replace the sort without touching consumers.
List<BundleIssue> todayIssues(
  List<BundleIssue> issues, {
  required String? assigneeDisplayName,
  required DateTime today,
}) {
  if (assigneeDisplayName == null) {
    return const [];
  }
  final endOfToday = DateTime(today.year, today.month, today.day, 23, 59, 59);
  final mine = [
    for (final issue in issues)
      if (issue.summary.assignedTo == assigneeDisplayName &&
          issue.summary.dueDate != null &&
          !issue.summary.dueDate!.isAfter(endOfToday))
        issue,
  ];
  mine.sort((a, b) {
    final byDue = a.summary.dueDate!.compareTo(b.summary.dueDate!);
    return byDue != 0 ? byDue : a.summary.id.compareTo(b.summary.id);
  });
  return mine;
}

/// Today's list for the signed-in user, derived from the loaded bundle.
final todayIssuesProvider = Provider.autoDispose<List<BundleIssue>>((ref) {
  final issues = ref.watch(issuesProvider).value?.sorted ?? const [];
  final user = ref.watch(connectionManagerProvider).value?.active?.currentUser;
  return todayIssues(
    issues,
    assigneeDisplayName: user?.displayName,
    today: DateTime.now(),
  );
});
