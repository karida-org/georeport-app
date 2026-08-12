import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/geojson.dart';
import '../../../api/models/issue_document.dart';
import '../../../api/models/project_schema.dart';
import '../../capture/capture_providers.dart';
import '../../capture/custom_field_editor.dart';
import '../../capture/location_picker_screen.dart';
import '../issue_providers.dart';
import '../issue_update.dart';

/// Opens the field editor for an issue, full screen (it carries more than a
/// sheet comfortably holds).
Future<void> showEditIssueScreen(
  BuildContext context, {
  required IssueDocument issue,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => EditIssueScreen(issue: issue),
    ),
  );
}

/// Edits what the per-user contract and the project schema both allow:
/// subject, description, priority, assignee, due date, progress, the
/// supported custom field formats, and a point issue's location through the
/// existing picker (line/polygon redrawing needs a drawing tool and stays a
/// follow-up). Only changed fields are sent, with the loaded lock_version,
/// so stale edits surface as conflicts instead of overwriting.
class EditIssueScreen extends ConsumerStatefulWidget {
  const EditIssueScreen({required this.issue, super.key});

  final IssueDocument issue;

  @override
  ConsumerState<EditIssueScreen> createState() => _EditIssueScreenState();
}

class _EditIssueScreenState extends ConsumerState<EditIssueScreen> {
  late final TextEditingController _subject = TextEditingController(
    text: widget.issue.subject,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.issue.description ?? '',
  );
  late int? _priorityId = widget.issue.priority?.id;
  late int? _assigneeId = widget.issue.assignedTo?.id;
  late DateTime? _dueDate = widget.issue.dueDate;
  late int _doneRatio = widget.issue.doneRatio;
  late LatLng? _location = _initialLocation;
  bool _locationChanged = false;
  late final Map<int, Object?> _customValues = {
    for (final field in widget.issue.customFields)
      field.id: field.values.length > 1
          ? List<String>.of(field.values)
          : field.values.firstOrNull,
  };
  final Set<int> _customChanged = {};
  late int _lockVersion = widget.issue.lockVersion;
  bool _saving = false;

  LatLng? get _initialLocation =>
      widget.issue.geometry is PointGeometry &&
          (widget.issue.geometry! as PointGeometry).points.isNotEmpty
      ? (widget.issue.geometry! as PointGeometry).points.first
      : null;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  bool _can(ProjectSchema schema, String field) =>
      widget.issue.editable.fields.contains(field) &&
      schema.writable.contains(field);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final schema = ref.watch(projectSchemaProvider(widget.issue.project.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editIssueTitle),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(context),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
      body: schema.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(l10n.issuesLoadFailed('$error'))),
        data: (schema) => _form(context, l10n, schema),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    AppLocalizations l10n,
    ProjectSchema schema,
  ) {
    final dateFormat = DateFormat.yMMMd(l10n.localeName);
    final priorities = schema.references['priority_id'] ?? const [];
    final assignees = schema.references['assigned_to_id'] ?? const [];
    final customFields = schema.fieldsForTracker(widget.issue.tracker.id);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_can(schema, 'subject'))
          TextField(
            controller: _subject,
            decoration: InputDecoration(
              labelText: l10n.captureSubjectLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        if (_can(schema, 'description')) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: l10n.captureDescriptionLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (_can(schema, 'priority_id') && priorities.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _priorityId,
            decoration: InputDecoration(
              labelText: l10n.issuePriorityLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final option in priorities)
                DropdownMenuItem(value: option.id, child: Text(option.name)),
            ],
            onChanged: (value) => setState(() => _priorityId = value),
          ),
        ],
        if (_can(schema, 'assigned_to_id') && assignees.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _assigneeId,
            decoration: InputDecoration(
              labelText: l10n.issueAssigneeLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.captureFieldNone)),
              for (final option in assignees)
                DropdownMenuItem(value: option.id, child: Text(option.name)),
            ],
            onChanged: (value) => setState(() => _assigneeId = value),
          ),
        ],
        if (_can(schema, 'due_date')) ...[
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.issueDueDateLabel,
              border: const OutlineInputBorder(),
              suffixIcon: _dueDate == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.editIssueClearDue,
                      onPressed: () => setState(() => _dueDate = null),
                    ),
            ),
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _dueDate = picked);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _dueDate == null
                      ? l10n.captureFieldNone
                      : dateFormat.format(_dueDate!),
                ),
              ),
            ),
          ),
        ],
        if (_can(schema, 'done_ratio')) ...[
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: '${l10n.issueDoneRatioLabel}: $_doneRatio%',
              border: const OutlineInputBorder(),
            ),
            child: Slider(
              value: _doneRatio.toDouble(),
              max: 100,
              divisions: 10,
              label: '$_doneRatio%',
              onChanged: (value) => setState(() => _doneRatio = value.round()),
            ),
          ),
        ],
        if (_can(schema, 'geojson') && _initialLocation != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: Text(
              _locationChanged
                  ? l10n.editIssueLocationChanged
                  : l10n.editIssueAdjustLocation,
            ),
            onPressed: () async {
              final picked = await Navigator.of(context).push<LatLng>(
                MaterialPageRoute(
                  builder: (context) =>
                      LocationPickerScreen(initial: _location),
                ),
              );
              if (picked != null) {
                setState(() {
                  _location = picked;
                  _locationChanged = true;
                });
              }
            },
          ),
        ],
        if (_can(schema, 'custom_field_values'))
          for (final field in customFields)
            if (supportedCustomFieldFormats.contains(field.fieldFormat)) ...[
              const SizedBox(height: 16),
              CustomFieldEditor(
                field: field,
                value: _customValues[field.id],
                onChanged: (value) => setState(() {
                  _customValues[field.id] = value;
                  _customChanged.add(field.id);
                }),
              ),
            ],
        const SizedBox(height: 32),
      ],
    );
  }

  /// Only what changed goes on the wire; Redmine clears a value with ''.
  Map<String, dynamic> _changedFields() {
    final issue = widget.issue;
    final fields = <String, dynamic>{};
    final subject = _subject.text.trim();
    if (subject.isNotEmpty && subject != issue.subject) {
      fields['subject'] = subject;
    }
    final description = _description.text;
    if (description != (issue.description ?? '')) {
      fields['description'] = description;
    }
    if (_priorityId != issue.priority?.id && _priorityId != null) {
      fields['priority_id'] = _priorityId;
    }
    if (_assigneeId != issue.assignedTo?.id) {
      fields['assigned_to_id'] = _assigneeId == null ? '' : '$_assigneeId';
    }
    final originalDue = issue.dueDate;
    if (_dueDate != originalDue) {
      fields['due_date'] = _dueDate == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(_dueDate!);
    }
    if (_doneRatio != issue.doneRatio) {
      fields['done_ratio'] = _doneRatio;
    }
    if (_customChanged.isNotEmpty) {
      fields['custom_fields'] = [
        for (final id in _customChanged)
          {'id': id, 'value': _customValues[id] ?? ''},
      ];
    }
    final location = _location;
    if (_locationChanged && location != null) {
      fields['geojson'] =
          '{"type":"Feature","geometry":{"type":"Point",'
          '"coordinates":[${location.longitude},${location.latitude}]},'
          '"properties":{}}';
    }
    return fields;
  }

  Future<void> _save(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final fields = _changedFields();
    if (fields.isEmpty) {
      navigator.pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(issueUpdaterProvider)
          .submit(
            issueId: widget.issue.id,
            lockVersion: _lockVersion,
            fields: fields,
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.editIssueSaved)));
      if (mounted) {
        navigator.pop();
      }
    } on StaleIssueException {
      // The conflict already reloaded the document; adopt its fresh lock
      // version so a retry after review can succeed.
      var refreshed = _lockVersion;
      try {
        final fresh = await ref.read(
          issueDocumentProvider(widget.issue.id).future,
        );
        refreshed = fresh.lockVersion;
        // Offline right after a conflict: keep the old version; the next
        // retry surfaces the conflict again rather than crashing here.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
      if (mounted) {
        setState(() => _lockVersion = refreshed);
        messenger.showSnackBar(SnackBar(content: Text(l10n.issueConflictBody)));
      }
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.editIssueFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
