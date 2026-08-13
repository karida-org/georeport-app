import '../../api/models/issue_document.dart';

/// Whether the quick-log sheet may open for [document].
///
/// Two permissions have to agree, and they come from different places, which
/// is why this is worth naming rather than inlining:
///
/// - the server has the time-entry contract at all ([serverAllowsCreate])
/// - this user may log time on this particular issue
///
/// [alreadyOpened] keeps the sheet from opening twice when the document
/// arrives more than once (a refresh, or a retry after an error).
///
/// Opening it without the last two would put the user in front of a form the
/// server answers with 403. The feature hides instead.
bool canOpenQuickLog({
  required bool alreadyOpened,
  required bool serverAllowsCreate,
  required IssueDocument document,
}) {
  return !alreadyOpened && serverAllowsCreate && document.editable.canLogTime;
}
