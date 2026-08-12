import 'package:go_router/go_router.dart';

import 'features/capture/capture_screen.dart';
import 'features/connect/connect_screen.dart';
import 'features/issues/issue_detail_screen.dart';
import 'features/issues/issues_screen.dart';
import 'features/outbox/outbox_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ConnectScreen()),
    GoRoute(
      path: '/capture',
      builder: (context, state) => CaptureScreen(
        // Shared images arrive as cache file paths via the share intake.
        initialPhotoPaths: switch (state.extra) {
          final List<String> paths => paths,
          _ => const [],
        },
      ),
    ),
    GoRoute(path: '/outbox', builder: (context, state) => const OutboxScreen()),
    GoRoute(
      path: '/issues',
      builder: (context, state) => const IssuesScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => IssueDetailScreen(
            issueId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    ),
  ],
);
