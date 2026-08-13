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
    final rawBytes = reply.rawBytes;
    if (rawBytes != null) {
      return ResponseBody.fromBytes(
        rawBytes,
        reply.statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
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
  const ScriptedReply(this.statusCode, [this.body = const {}])
    : rawBytes = null;

  /// A reply served as raw bytes, for the binary path.
  ///
  /// Bytes rather than a string because a string would go through UTF-8, which
  /// cannot carry an arbitrary byte (0xFF alone is not valid UTF-8). An image
  /// is exactly that kind of payload, so a test asserting the bytes arrive
  /// intact has to be able to send ones that text could not represent.
  const ScriptedReply.bytes(this.statusCode, List<int> this.rawBytes)
    : body = const <String, dynamic>{};

  final int statusCode;
  final Object body;
  final List<int>? rawBytes;
}
