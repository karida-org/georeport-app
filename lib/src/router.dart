import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'features/capture/capture_screen.dart';
import 'features/connect/connect_screen.dart';
import 'features/home/dashboard_screen.dart';
import 'features/issues/issue_detail_screen.dart';
import 'features/issues/issues_screen.dart';
import 'features/issues/map_screen.dart';
import 'features/outbox/outbox_screen.dart';
import 'features/time/time_screen.dart';
import 'shell/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ConnectScreen()),
    // Full-screen flows above the shell: capture, outbox, and issue detail
    // push on the root navigator, so the bottom bar steps aside while the
    // user is inside a task.
    GoRoute(
      path: '/capture',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CaptureScreen(
        // Shared images arrive as cache file paths via the share intake.
        initialPhotoPaths: switch (state.extra) {
          final List<String> paths => paths,
          _ => const [],
        },
      ),
    ),
    GoRoute(
      path: '/outbox',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OutboxScreen(),
    ),
    GoRoute(
      path: '/issues/:id',
      parentNavigatorKey: _rootNavigatorKey,
      // A non-numeric id (bad deep link) falls back to the list instead of
      // throwing while the route builds.
      redirect: (context, state) =>
          int.tryParse(state.pathParameters['id'] ?? '') == null
          ? '/issues'
          : null,
      builder: (context, state) =>
          IssueDetailScreen(issueId: int.parse(state.pathParameters['id']!)),
    ),
    // The signed-in shell: Home, Issues, Map, and Time as stateful branches
    // behind the bottom bar (branch order defines the indices used by
    // GeoreportBottomBar and AppShell).
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/issues',
              // The map used to be a tab here; keep old deep links working.
              redirect: (context, state) =>
                  state.uri.queryParameters['tab'] == 'map' ? '/map' : null,
              builder: (context, state) => const IssuesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/time',
              builder: (context, state) => const TimeScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
