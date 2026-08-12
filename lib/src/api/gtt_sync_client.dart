import 'package:dio/dio.dart';

import 'base_url.dart';
import 'client_auth.dart';
import 'models/bundle.dart';
import 'models/capabilities.dart';
import 'models/issue_document.dart';

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
