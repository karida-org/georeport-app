import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../connections/connection_manager.dart';

/// Sends the user back to the connect screen once the active session ends.
///
/// Every screen behind a session needs this: signing out, or a session that
/// the server has invalidated, must not leave the user looking at a screen
/// whose data is no longer readable. Call it first thing in `build`.
///
/// The `context.mounted` check is what makes it safe to call from anywhere.
/// The listener can fire while the screen is being popped, and navigating
/// from a context that is no longer in the tree throws.
void watchSessionEnd(WidgetRef ref, BuildContext context) {
  ref.listen(connectionManagerProvider, (previous, next) {
    final state = next.value;
    // A null value means "still loading", which is not the same as
    // "no active connection" and must not navigate.
    if (state != null && state.active == null && context.mounted) {
      context.go('/');
    }
  });
}
