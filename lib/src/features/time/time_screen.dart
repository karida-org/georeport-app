import 'package:flutter/material.dart';

import 'time_summary_card.dart';
import 'timers_card.dart';

/// The Time destination: running and paused timers plus the personal time
/// summaries, in one place; the shell provides the scaffold and app bar.
class TimeScreen extends StatelessWidget {
  const TimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [TimersCard(), TimeSummaryCard()],
    );
  }
}
