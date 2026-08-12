import 'geojson.dart';
import 'issue_summary.dart';

/// One issue from a bundle: its summary plus geometry (null when unplaced).
class BundleIssue {
  const BundleIssue({required this.summary, this.geometry, this.geometryJson});

  final IssueSummary summary;
  final IssueGeometry? geometry;

  /// The untouched GeoJSON geometry object, preserved for map engines that
  /// consume GeoJSON sources directly (the typed [geometry] drops Multi*
  /// details such as polygon holes).
  final Map<String, dynamic>? geometryJson;

  bool get isPlaced => geometry != null;
}

class BundleProject {
  const BundleProject({
    required this.id,
    required this.identifier,
    required this.name,
    required this.hasBoundary,
  });

  factory BundleProject.fromJson(Map<String, dynamic> json) {
    return BundleProject(
      id: (json['id'] as num).toInt(),
      identifier: json['identifier'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hasBoundary: json['has_boundary'] == true || json['boundary'] != null,
    );
  }

  final int id;
  final String identifier;
  final String name;
  final bool hasBoundary;

  /// The compact shape the offline cache stores; [fromJson] reads it back
  /// (`has_boundary` is written as the derived boolean).
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'identifier': identifier,
    'name': name,
    'has_boundary': hasBoundary,
  };
}

/// Parsed bundle response. Handles both the cross-project form
/// (`GET /gtt_sync/bundle`, with a `projects` list) and the single-project
/// form (`GET /gtt_sync/projects/:id/bundle`, with one `project` object).
class Bundle {
  const Bundle({required this.issues, required this.projects});

  factory Bundle.fromJson(Map<String, dynamic> json) {
    final issuesJson = json['issues'] as Map<String, dynamic>? ?? const {};
    final issues = <BundleIssue>[
      for (final key in const ['point', 'line', 'polygon'])
        ..._featureCollection(issuesJson[key]),
      for (final unplaced
          in issuesJson['unplaced'] as List<dynamic>? ?? const <dynamic>[])
        BundleIssue(
          summary: IssueSummary.fromJson(unplaced as Map<String, dynamic>),
        ),
    ]..sort((a, b) => b.summary.id.compareTo(a.summary.id));

    final projectsJson = json['projects'] as List<dynamic>?;
    final singleProject = json['project'] as Map<String, dynamic>?;
    final projects = projectsJson != null
        ? [
            for (final project in projectsJson)
              BundleProject.fromJson(project as Map<String, dynamic>),
          ]
        : [if (singleProject != null) BundleProject.fromJson(singleProject)];

    return Bundle(issues: issues, projects: projects);
  }

  final List<BundleIssue> issues;
  final List<BundleProject> projects;

  Iterable<BundleIssue> get placed => issues.where((issue) => issue.isPlaced);

  Iterable<BundleIssue> get unplaced =>
      issues.where((issue) => !issue.isPlaced);
}

Iterable<BundleIssue> _featureCollection(Object? raw) {
  final collection = raw as Map<String, dynamic>?;
  final features = collection?['features'] as List<dynamic>? ?? const [];
  return features.map((feature) {
    final featureJson = feature as Map<String, dynamic>;
    final geometryJson = featureJson['geometry'] as Map<String, dynamic>?;
    return BundleIssue(
      summary: IssueSummary.fromJson(
        featureJson['properties'] as Map<String, dynamic>,
      ),
      geometry: IssueGeometry.fromJson(geometryJson),
      geometryJson: geometryJson,
    );
  });
}
