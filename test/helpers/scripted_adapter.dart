import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A Dio adapter that answers from a script and records what it was asked.
///
/// Preferred over a mocking package: the tests that need it are about how the
/// client behaves across a sequence of responses (a 401 then a 200), which
/// reads more clearly as a list of replies than as expectation setup.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.replies);

  /// Returned in order, one per request. The last reply repeats if more
  /// requests arrive, so a test only scripts as far as it cares about.
  final List<ScriptedReply> replies;

  /// Every request seen, in order, for asserting on headers and retries.
  final List<SeenRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(SeenRequest.from(options));
    final reply = requests.length <= replies.length
        ? replies[requests.length - 1]
        : replies.last;
    final rawBody = reply.rawBody;
    return ResponseBody.fromString(
      rawBody ?? jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [
          rawBody == null
              ? Headers.jsonContentType
              : Headers.textPlainContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A snapshot of one outgoing request.
///
/// Copied rather than held by reference on purpose: a retry replays the same
/// [RequestOptions] instance after mutating its headers, so keeping the object
/// would make every recorded request show the *last* set of headers and hide
/// exactly the difference these tests are checking.
class SeenRequest {
  SeenRequest.from(RequestOptions options)
    : uri = options.uri,
      method = options.method,
      body = options.data,
      headers = Map<String, dynamic>.from(options.headers);

  final Uri uri;
  final String method;

  /// The request payload as the caller passed it, before serialization.
  final Object? body;
  final Map<String, dynamic> headers;
}

class ScriptedReply {
  /// A JSON reply: [body] is encoded and served as `application/json`.
  const ScriptedReply(this.statusCode, [this.body = const {}]) : rawBody = null;

  /// A reply served verbatim, for the binary path where the exact bytes on
  /// the wire are what the caller receives.
  const ScriptedReply.raw(this.statusCode, String this.rawBody)
    : body = const <String, dynamic>{};

  final int statusCode;
  final Object body;
  final String? rawBody;
}
