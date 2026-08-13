import 'package:dio/dio.dart';
import 'package:georeport/src/api/issue_submit_api.dart';

/// A scripted [IssueSubmitApi], so the queue's state machine can be driven
/// through the outcomes that matter without a server.
///
/// Each hook either returns a value or throws whatever it was handed. The
/// call counters are how the tests tell "retried" from "gave up", and
/// "adopted an existing issue" from "created a second one".
class FakeSubmitApi implements IssueSubmitApi {
  FakeSubmitApi({
    this.uploadToken = 'tok',
    this.uploadError,
    this.issueId = 100,
    this.createError,
    this.existing = const [],
    this.lookupError,
  });

  String uploadToken;
  Exception? uploadError;

  int issueId;
  Exception? createError;

  /// What the dedup probe finds.
  List<CreatedIssue> existing;
  Exception? lookupError;

  final List<String> uploadedFilenames = [];
  final List<Map<String, dynamic>> createdPayloads = [];
  int lookupCalls = 0;

  int get uploads => uploadedFilenames.length;
  int get creates => createdPayloads.length;

  @override
  Future<String> uploadFile(List<int> bytes, String filename) async {
    uploadedFilenames.add(filename);
    if (uploadError case final Exception error) {
      throw error;
    }
    return uploadToken;
  }

  @override
  Future<int> createIssue(Map<String, dynamic> payload) async {
    createdPayloads.add(payload);
    if (createError case final Exception error) {
      throw error;
    }
    return issueId;
  }

  @override
  Future<List<CreatedIssue>> myIssuesCreatedSince({
    required int projectId,
    required DateTime since,
  }) async {
    lookupCalls += 1;
    if (lookupError case final Exception error) {
      throw error;
    }
    return existing;
  }
}

/// A [DioException] of the given shape, since the submitter classifies on
/// exception type and status code rather than on message text.
DioException dioError({int? status, DioExceptionType? type, Object? data}) {
  final options = RequestOptions(path: '/issues.json');
  return DioException(
    requestOptions: options,
    type: type ?? DioExceptionType.badResponse,
    response: status == null
        ? null
        : Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: data,
          ),
  );
}
