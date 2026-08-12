import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/connection_manager.dart';
import '../issues/issue_providers.dart';

/// What the connected server offers for time tracking, so every entry point
/// degrades cleanly against servers without the contract.
final timeCapabilitiesProvider =
    Provider.autoDispose<({bool canList, bool canCreate})>((ref) {
      final capabilities = ref
          .watch(connectionManagerProvider)
          .value
          ?.active
          ?.capabilities;
      return (
        canList: capabilities?.supports('time_entries') ?? false,
        canCreate: capabilities?.supports('time_entry_create') ?? false,
      );
    });

/// One tick per second while watched; drives the running timer display.
final tickerProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().toUtc(),
  ),
);

/// Hours logged today and this week (Monday start), from the contract's
/// own-entries index. Invalidated after every successful quick log.
final myTimeSummaryProvider =
    FutureProvider.autoDispose<({double today, double week})>((ref) async {
      final client = ref.watch(activeClientProvider);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final todayPage = await client.timeEntries(from: today);
      final weekPage = await client.timeEntries(from: weekStart);
      return (today: todayPage.totalHours, week: weekPage.totalHours);
    });
