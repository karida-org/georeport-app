import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/connection_manager.dart';

/// Which slice of the loaded issues My Work shows.
enum MyWorkFilter { today, mine, all }

/// Defaults to "mine" when the signed-in account is known; the whole filter
/// is hidden (and everything shown) when it is not. Shared by the list and
/// map screens, so switching between them keeps the selection.
final myWorkFilterProvider =
    NotifierProvider<MyWorkFilterNotifier, MyWorkFilter>(
      MyWorkFilterNotifier.new,
    );

class MyWorkFilterNotifier extends Notifier<MyWorkFilter> {
  @override
  MyWorkFilter build() {
    final user = ref
        .watch(connectionManagerProvider)
        .value
        ?.active
        ?.currentUser;
    return user == null ? MyWorkFilter.all : MyWorkFilter.mine;
  }

  void select(MyWorkFilter filter) => state = filter;
}
