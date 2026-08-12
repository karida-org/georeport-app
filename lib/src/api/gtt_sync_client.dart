import 'package:dio/dio.dart';

import 'models/bundle.dart';
import 'models/capabilities.dart';
import 'models/issue_document.dart';

/// Thin HTTP client for the `redmine_gtt_sync` contract.
///
/// One instance per connected Redmine instance. Authentication uses the
/// Redmine API key header; OAuth arrives with the M1 onboarding work.
class GttSyncClient {
  GttSyncClient({required String baseUrl, String? apiKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalize(baseUrl),
              headers: {
                if (apiKey != null && apiKey.isNotEmpty)
                  'X-Redmine-API-Key': apiKey,
                'Accept': 'application/json',
              },
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  static String _normalize(String url) {
    var normalized = url.trim();
    if (!normalized.contains('://')) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

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

  /// Raw GTT styling settings (tracker icons, tile layers).
  ///
  /// This is a `redmine_gtt` baseline endpoint, not part of the gtt_sync
  /// contract; treat everything in it as optional decoration.
  Future<Map<String, dynamic>> gttSettings() async {
    final response = await _dio.get<Map<String, dynamic>>('/gtt/settings.json');
    return response.data ?? const {};
  }
}
