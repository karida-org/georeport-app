import 'package:flutter/material.dart';

import 'issues_view.dart';

/// The Map destination: the loaded issues on the map, sharing the My Work
/// filter and data with the Issues list; the shell provides the scaffold
/// and app bar.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IssuesView(mode: IssuesViewMode.map);
  }
}
