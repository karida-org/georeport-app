import 'package:flutter/material.dart';

import 'issues_view.dart';

/// The Issues destination: the loaded issues as a filterable list. The map
/// presentation of the same data lives on its own destination (MapScreen);
/// the shell provides the scaffold and app bar.
class IssuesScreen extends StatelessWidget {
  const IssuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IssuesView(mode: IssuesViewMode.list);
  }
}
