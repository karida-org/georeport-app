import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/project_schema.dart';
import '../../connections/active_client.dart';
import '../../time/timers_notifier.dart';
import '../capture/capture_providers.dart';
import 'time_providers.dart';

/// Opens the quick-log sheet for an issue. Prefills the hours from the
/// issue's timer when one exists; a successful log removes that timer.
/// Recording time must be cheaper than not recording it: with the defaults
/// (prefilled hours, project-default activity, today) the common case is
/// open, submit.
Future<void> showQuickLogSheet(
  BuildContext context, {
  required int issueId,
  required int projectId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _QuickLogSheet(issueId: issueId, projectId: projectId),
    ),
  );
}

class _QuickLogSheet extends ConsumerStatefulWidget {
  const _QuickLogSheet({required this.issueId, required this.projectId});

  final int issueId;
  final int projectId;

  @override
  ConsumerState<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends ConsumerState<_QuickLogSheet> {
  late final TextEditingController _hours;
  final _comment = TextEditingController();
  int? _activityId;
  late DateTime _spentOn;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final timer = ref.read(timersProvider.notifier).timerFor(widget.issueId);
    final now = DateTime.now().toUtc();
    final elapsed = timer?.elapsed(now) ?? Duration.zero;
    // Prefill from the timer, rounded up to the minute so a just-started
    // timer never logs zero.
    final hours = elapsed == Duration.zero
        ? ''
        : ((elapsed.inSeconds / 60).ceil() / 60).toStringAsFixed(2);
    _hours = TextEditingController(text: hours);
    _spentOn = (timer?.startedAt ?? now).toLocal();
  }

  @override
  void dispose() {
    _hours.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(TimeEntrySection section) async {
    final l10n = AppLocalizations.of(context);
    final hours = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    if (hours == null || hours <= 0) {
      setState(() => _error = l10n.timeHoursInvalid);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final activityId = _activityId ?? section.defaultActivity?.id;
    try {
      await ref.read(activeClientProvider).createTimeEntry(widget.issueId, {
        'hours': hours,
        'activity_id': ?activityId,
        'spent_on': _spentOn.toIso8601String().split('T').first,
        if (_comment.text.trim().isNotEmpty) 'comments': _comment.text.trim(),
      });
      await ref.read(timersProvider.notifier).stop(widget.issueId);
      ref.invalidate(myTimeSummaryProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.timeLogged)));
        Navigator.pop(context);
      }
      // Server-side validation and connectivity failures both land here;
      // the sheet stays open so nothing typed is lost.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.timeLogFailed('$error'));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final schema = ref.watch(projectSchemaProvider(widget.projectId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: schema.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => Text(l10n.timeLogFailed('$error')),
        data: (data) => _form(l10n, data.timeEntry),
      ),
    );
  }

  Widget _form(AppLocalizations l10n, TimeEntrySection section) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.timeLogTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hours,
                enabled: !_submitting,
                autofocus: _hours.text.isEmpty,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.timeHoursLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _submitting
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _spentOn,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null && mounted) {
                          setState(() => _spentOn = picked);
                        }
                      },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.timeSpentOnLabel,
                    border: const OutlineInputBorder(),
                  ),
                  child: Text(_spentOn.toIso8601String().split('T').first),
                ),
              ),
            ),
          ],
        ),
        if (section.activities.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _activityId ?? section.defaultActivity?.id,
            decoration: InputDecoration(
              labelText: l10n.timeActivityLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final activity in section.activities)
                DropdownMenuItem(
                  value: activity.id,
                  child: Text(activity.name),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _activityId = value),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _comment,
          enabled: !_submitting,
          decoration: InputDecoration(
            labelText: l10n.timeCommentLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _submitting ? null : () => _submit(section),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.timeLogButton),
        ),
      ],
    );
  }
}
