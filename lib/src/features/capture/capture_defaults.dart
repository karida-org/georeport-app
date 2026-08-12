import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Last-used capture defaults, kept across restarts so the next capture
/// starts where the previous one left off: the last project globally, and
/// the last tracker per project.
class CaptureDefaults {
  CaptureDefaults([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _projectKey = 'capture.lastProject';
  static String _trackerKey(int projectId) => 'capture.lastTracker.$projectId';

  Future<int?> lastProject() => _prefs.getInt(_projectKey);

  Future<int?> lastTracker(int projectId) =>
      _prefs.getInt(_trackerKey(projectId));

  Future<void> remember({
    required int projectId,
    required int trackerId,
  }) async {
    await _prefs.setInt(_projectKey, projectId);
    await _prefs.setInt(_trackerKey(projectId), trackerId);
  }
}

final captureDefaultsProvider = Provider<CaptureDefaults>(
  (ref) => CaptureDefaults(),
);

final lastProjectProvider = FutureProvider<int?>(
  (ref) => ref.watch(captureDefaultsProvider).lastProject(),
);

final lastTrackerProvider = FutureProvider.family<int?, int>(
  (ref, projectId) => ref.watch(captureDefaultsProvider).lastTracker(projectId),
);
