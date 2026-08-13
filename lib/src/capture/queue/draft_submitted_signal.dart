import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Announces that a queued draft became a real issue on the server.
///
/// The queue publishes; whoever shows issues subscribes. Expressed this way
/// round because the queue has no business knowing that an issue list exists:
/// it used to reach up into the issues feature and invalidate its provider,
/// which pointed the dependency arrow from core at a feature.
///
/// The value is a count rather than the issue id. Subscribers only need to
/// know that *something* landed, and a count cannot collide the way repeating
/// the same id would.
final draftSubmittedProvider = NotifierProvider<DraftSubmittedSignal, int>(
  DraftSubmittedSignal.new,
);

class DraftSubmittedSignal extends Notifier<int> {
  @override
  int build() => 0;

  void announce() => state = state + 1;
}
