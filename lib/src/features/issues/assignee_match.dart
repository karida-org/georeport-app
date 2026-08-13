import '../../api/models/issue_summary.dart';

/// Whether [summary] is assigned to the signed-in user.
///
/// Redmine renders a person's name through the instance's `user_format`
/// setting, so the same user reads as "John Smith", "Smith John",
/// "Smith, J." or "jsmith" depending on how that instance is configured.
/// A client that composes the name itself and compares strings therefore
/// matches nothing on most instances, and fails quietly: "Mine" and the
/// Today list simply come back empty, which looks like having no work.
///
/// The id answers the question the name cannot. The name is consulted only
/// when the server sent no id, which means a server older than the
/// `assigned_to_id` field.
bool isAssignedTo(
  IssueSummary summary, {
  required int? userId,
  required String? userDisplayName,
}) {
  final assigneeId = summary.assignedToId;
  if (assigneeId != null && userId != null) {
    return assigneeId == userId;
  }
  return userDisplayName != null && summary.assignedTo == userDisplayName;
}
