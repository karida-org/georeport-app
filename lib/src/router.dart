import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'features/capture/capture_screen.dart';
import 'features/connect/connect_screen.dart';
import 'features/home/dashboard_screen.dart';
import 'features/issues/issue_detail_screen.dart';
import 'features/issues/issues_screen.dart';
import 'features/outbox/outbox_screen.dart';
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
      builder: (context, state) =>
          IssueDetailScreen(issueId: int.parse(state.pathParameters['id']!)),
    ),
    // The signed-in shell: Home and Issues as stateful branches behind the
    // bottom navigation bar.
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
              builder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return IssuesScreen(
                  // Keyed so navigating with a different tab rebuilds even
                  // though the branch keeps the screen alive.
                  key: ValueKey('issues-${tab ?? 'list'}'),
                  initialTab: tab == 'map' ? 1 : 0,
                );
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
