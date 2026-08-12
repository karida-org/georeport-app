import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'base_url.dart';
import 'client_auth.dart';
import 'issue_submit_api.dart';
import 'models/bundle.dart';
import 'models/capabilities.dart';
import 'models/changes_page.dart';
import 'models/current_user.dart';
import 'models/gtt_style_settings.dart';
import 'models/issue_document.dart';
import 'models/project_schema.dart';
import 'models/time_entry.dart';

/// Thin HTTP client for the `redmine_gtt_sync` contract.
///
/// One instance per connected Redmine instance. [auth] is either a Redmine
/// API key or an OAuth token manager; omit it for the public capabilities
/// probe.
class GttSyncClient implements IssueSubmitApi {
  GttSyncClient({required String baseUrl, ClientAuth? auth, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: normalizeBaseUrl(baseUrl),
              headers: {'Accept': 'application/json'},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ) {
    auth?.install(_dio);
  }

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  /// Public feature-detection probe; works without credentials.
  Future<Capabilities> capabilities() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/capabilities',
    );
    return Capabilities.fromJson(response.data!);
  }

  /// The cross-project bundle: every project the user may integrate with.
  Future<Bundle> bundle() async {
    final response = await _dio.get<Map<String, dynamic>>('/gtt_sync/bundle');
    return Bundle.fromJson(response.data!);
  }

  /// The bundle for a single project.
  Future<Bundle> projectBundle(int projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/projects/$projectId/bundle',
    );
    return Bundle.fromJson(response.data!);
  }

  /// A single issue as a JSON-LD document.
  Future<IssueDocument> issueDocument(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/issues/$id',
    );
    return IssueDocument.fromJson(response.data!);
  }

  /// The delta feed: issues changed since [since] (a `next_since` token or an
  /// ISO 8601 time for the first call). With [knownIds], the response also
  /// carries the caller's full visible id set for deletion reconciliation.
  Future<ChangesPage> changes({
    required String since,
    bool knownIds = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/changes',
      queryParameters: {'since': since, if (knownIds) 'known_ids': '1'},
    );
    return ChangesPage.fromJson(response.data ?? const {});
  }

  /// Instance styling (tracker names/icons, status names/colors) from the
  /// `redmine_gtt` baseline. Optional decoration; failures yield defaults.
  Future<GttStyleSettings> styleSettings() async {
    return GttStyleSettings.fromJson(await gttSettings());
  }

  /// The authenticated account, from Redmine's core API. Outside the
  /// gtt_sync contract, but identity has no contract surface yet; callers
  /// must tolerate failure (a narrow token or role may forbid it).
  Future<CurrentUser> currentUser() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/current.json',
    );
    return CurrentUser.fromJson(response.data ?? const {});
  }

  /// Per-project editing schema for the current user.
  Future<ProjectSchema> projectSchema(int projectId) async =>
      ProjectSchema.fromJson(await projectSchemaJson(projectId));

  /// The raw schema document, exposed for the offline schema cache.
  Future<Map<String, dynamic>> projectSchemaJson(int projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/projects/$projectId/schema',
    );
    return response.data ?? const {};
  }

  /// Redmine's two-step attachment flow, step one: upload the bytes, get a
  /// token to reference on the issue write.
  @override
  Future<String> uploadFile(List<int> bytes, String filename) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/uploads.json',
      queryParameters: {'filename': filename},
      // Bytes, not a Stream: the 401-refresh interceptor retries the same
      // RequestOptions, and a single-subscription stream is already consumed
      // by then - the retry threw a StateError that the outbox recorded as a
      // permanent failure for an upload that would have succeeded.
      data: Uint8List.fromList(bytes),
      options: Options(
        contentType: 'application/octet-stream',
        headers: {'Content-Length': bytes.length},
      ),
    );
    final upload = response.data?['upload'];
    final token = upload is Map<String, dynamic>
        ? upload['token'] as String?
        : null;
    if (token == null || token.isEmpty) {
      throw StateError('Upload returned no token');
    }
    return token;
  }

  /// Creates an issue through the stock Redmine REST API (the contract has
  /// no write endpoints by design; workflow and permissions stay server-side)
  /// and returns the new issue id.
  @override
  Future<int> createIssue(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/issues.json',
      data: payload,
    );
    final issue = response.data?['issue'];
    final id = issue is Map<String, dynamic>
        ? (issue['id'] as num?)?.toInt()
        : null;
    if (id == null) {
      throw StateError('Issue creation returned no id');
    }
    return id;
  }

  /// Issues the current user authored in a project since a point in time,
  /// via the stock REST index. Fractional seconds are stripped because
  /// Redmine's `created_on` filter parser rejects them.
  @override
  Future<List<CreatedIssue>> myIssuesCreatedSince({
    required int projectId,
    required DateTime since,
  }) async {
    final stamp = since.toUtc().toIso8601String().split('.').first;
    final response = await _dio.get<Map<String, dynamic>>(
      '/issues.json',
      queryParameters: {
        'project_id': projectId,
        'author_id': 'me',
        'status_id': '*',
        'created_on': '>=${stamp}Z',
        'limit': 100,
      },
    );
    final issues = response.data?['issues'];
    if (issues is! List) {
      return const [];
    }
    return [
      for (final issue in issues.whereType<Map<String, dynamic>>())
        if ((issue['id'] as num?)?.toInt() case final int id)
          (id: id, subject: issue['subject'] as String? ?? ''),
    ];
  }

  /// Updates an issue through the stock Redmine REST API. The payload must
  /// carry lock_version: Redmine's optimistic locking is what keeps a stale
  /// client from silently overwriting someone else's change.
  Future<void> updateIssue(int issueId, Map<String, dynamic> payload) async {
    await _dio.put<void>('/issues/$issueId.json', data: payload);
  }

  /// Publishes the signed-in user's current location. The server always
  /// writes the caller's own point (there is no id in the path), keeping
  /// only the latest one, so nothing resembling a track is ever stored.
  Future<void> publishLocation(double latitude, double longitude) async {
    await _dio.post<void>(
      '/gtt_sync/users/me/location',
      data: {
        'location': {
          'type': 'Point',
          'coordinates': [longitude, latitude],
        },
      },
    );
  }

  /// Logs time on an issue through the contract; runs as the authenticated
  /// user. Returns the created entry. A 422 carries the server's validation
  /// messages in the DioException response.
  Future<TimeEntry> createTimeEntry(
    int issueId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/gtt_sync/issues/$issueId/time_entries',
      data: payload,
    );
    return TimeEntry.fromJson(response.data ?? const {});
  }

  /// The authenticated user's own time entries for a date range; totals in
  /// the page cover the whole range even when the list is capped.
  Future<TimeEntriesPage> timeEntries({DateTime? from, DateTime? to}) async {
    String day(DateTime date) => date.toIso8601String().split('T').first;
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/time_entries',
      queryParameters: {
        if (from != null) 'from': day(from),
        if (to != null) 'to': day(to),
      },
    );
    return TimeEntriesPage.fromJson(response.data ?? const {});
  }

  /// Authenticated binary fetch for same-instance assets (attachment
  /// thumbnails and downloads). Absolute URLs are reduced to their path so
  /// the request always goes to this client's own instance with its
  /// credentials, regardless of the canonical host the server advertises.
  Future<Uint8List> fetchBytes(String urlOrPath) async {
    final uri = Uri.parse(urlOrPath);
    // dio concatenates baseUrl + path, so an absolute URL must be reduced to
    // the part BELOW the base. On a Redmine hosted at /redmine, keeping the
    // whole path asked for /redmine/redmine/... and every attachment 404ed.
    final basePath = Uri.parse(_dio.options.baseUrl).path;
    var path = uri.hasScheme ? uri.path : urlOrPath;
    if (uri.hasScheme && basePath.isNotEmpty && basePath != '/') {
      final prefix = basePath.endsWith('/')
          ? basePath.substring(0, basePath.length - 1)
          : basePath;
      if (path.startsWith('$prefix/')) {
        path = path.substring(prefix.length);
      }
    }
    final response = await _dio.get<List<int>>(
      path,
      queryParameters: uri.hasScheme ? uri.queryParameters : null,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  /// Cheapest authenticated call on the contract, used to verify credentials
  /// before persisting them: the change feed with a now-cursor returns an
  /// empty page, but only for a caller Redmine accepts.
  Future<void> validateAuth() async {
    await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/changes',
      queryParameters: {'since': DateTime.now().toUtc().toIso8601String()},
    );
  }

  /// Raw GTT styling settings (tracker icons, tile layers).
  ///
  /// This is a `redmine_gtt` baseline endpoint, not part of the gtt_sync
  /// contract; treat everything in it as optional decoration.
  Future<Map<String, dynamic>> gttSettings() async {
    final response = await _dio.get<Map<String, dynamic>>('/gtt/settings.json');
    return response.data ?? const {};
  }
}
