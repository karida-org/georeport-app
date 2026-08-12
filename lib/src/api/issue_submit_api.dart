/// A recently created issue, as much of it as deduplication needs.
typedef CreatedIssue = ({int id, String subject});

/// The slice of the API an issue submission needs. The upload queue depends
/// on this interface instead of the full client so its state machine can be
/// exercised against a fake in tests.
abstract interface class IssueSubmitApi {
  /// Uploads bytes and returns the attachment token to reference on create.
  Future<String> uploadFile(List<int> bytes, String filename);

  /// Creates an issue and returns its id.
  Future<int> createIssue(Map<String, dynamic> payload);

  /// Issues the current user created in [projectId] on or after [since].
  /// Used to resolve an interrupted create without duplicating the issue.
  Future<List<CreatedIssue>> myIssuesCreatedSince({
    required int projectId,
    required DateTime since,
  });
}
