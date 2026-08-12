import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'base_url.dart';
import 'client_auth.dart';
import 'models/bundle.dart';
import 'models/capabilities.dart';
import 'models/changes_page.dart';
import 'models/current_user.dart';
import 'models/gtt_style_settings.dart';
import 'models/issue_document.dart';
import 'models/project_schema.dart';

/// Thin HTTP client for the `redmine_gtt_sync` contract.
///
/// One instance per connected Redmine instance. [auth] is either a Redmine
/// API key or an OAuth token manager; omit it for the public capabilities
/// probe.
class GttSyncClient {
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
  Future<ProjectSchema> projectSchema(int projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gtt_sync/projects/$projectId/schema',
    );
    return ProjectSchema.fromJson(response.data ?? const {});
  }

  /// Redmine's two-step attachment flow, step one: upload the bytes, get a
  /// token to reference on the issue write.
  Future<String> uploadFile(List<int> bytes, String filename) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/uploads.json',
      queryParameters: {'filename': filename},
      data: Stream.fromIterable([bytes]),
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

  /// Authenticated binary fetch for same-instance assets (attachment
  /// thumbnails and downloads). Absolute URLs are reduced to their path so
  /// the request always goes to this client's own instance with its
  /// credentials, regardless of the canonical host the server advertises.
  Future<Uint8List> fetchBytes(String urlOrPath) async {
    final uri = Uri.parse(urlOrPath);
    final path = uri.hasScheme ? uri.path : urlOrPath;
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
