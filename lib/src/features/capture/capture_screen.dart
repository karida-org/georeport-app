import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';
import '../../api/models/project_schema.dart';
import '../../capture/custom_field_values.dart';
import '../../capture/device_location.dart';
import '../../capture/exif_location.dart';
import '../../capture/issue_draft.dart';
import '../../capture/queue/upload_queue.dart';
import '../../media/mime.dart';
import '../../shell/session_guard.dart';
import '../issues/issues_store.dart';
import 'capture_defaults.dart';
import 'capture_providers.dart';
import 'capture_steps.dart';
import 'capture_widgets.dart';
import 'custom_field_editor.dart';
import 'location_picker_screen.dart';

/// Where a draft location came from, shown as context under the coordinates.

/// The capture flow: photos first, then a minimal schema-driven form.
/// Required fields surface automatically; everything optional folds away.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({this.initialPhotoPaths = const [], super.key});

  /// Image files to attach on open: the Android share target lands here
  /// with the shared photos already copied into the cache directory.
  final List<String> initialPhotoPaths;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _picker = ImagePicker();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();

  final List<DraftPhoto> _photos = [];
  int? _projectId;
  int? _trackerId;
  LatLng? _location;
  CaptureLocationSource _locationSource = CaptureLocationSource.manual;
  bool _locating = false;
  bool _showOptionalFields = false;
  final Map<int, Object> _customFieldValues = {};
  CaptureStep _step = CaptureStep.photos;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhotoPaths.isNotEmpty) {
      unawaited(_loadSharedPhotos(widget.initialPhotoPaths));
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Attaches images handed over by the share target. Unreadable files are
  /// skipped; the user still lands on a working capture form.
  Future<void> _loadSharedPhotos(List<String> paths) async {
    final photos = <DraftPhoto>[];
    for (final path in paths) {
      try {
        final name = path.split('/').last;
        photos.add(
          DraftPhoto(
            filename: name,
            bytes: await File(path).readAsBytes(),
            contentType: mimeForFilename(name),
          ),
        );
      } on Exception {
        continue;
      }
    }
    if (mounted) {
      await _ingestPhotos(photos);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final images = source == ImageSource.gallery
          ? await _picker.pickMultiImage()
          : [await _picker.pickImage(source: source)].nonNulls.toList();
      final photos = <DraftPhoto>[];
      for (final image in images) {
        photos.add(
          DraftPhoto(
            filename: image.name,
            bytes: await image.readAsBytes(),
            contentType: image.mimeType ?? mimeForFilename(image.name),
          ),
        );
      }
      if (mounted) {
        await _ingestPhotos(photos);
      }
      // Camera unavailable, permission denied, unreadable file: platform
      // exceptions here are user-visible situations, not programming errors.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.capturePhotoAddFailed('$error'));
      }
    }
  }

  /// The shared intake path for picked and shared photos: attach them, then
  /// suggest a location from the first geotagged photo, falling back to the
  /// device position when permission is already granted; a permission
  /// dialog must never interrupt the photo flow uninvited.
  Future<void> _ingestPhotos(List<DraftPhoto> photos) async {
    for (final photo in photos) {
      if (!mounted) {
        return;
      }
      setState(() => _photos.add(photo));
      // First geotagged photo wins the location suggestion; the user can
      // still adjust or clear it.
      if (_location == null) {
        final suggested = await exifLocationOf(photo.bytes);
        if (suggested != null && mounted) {
          setState(() {
            _location = suggested;
            _locationSource = CaptureLocationSource.exif;
          });
        }
      }
    }
    if (photos.isNotEmpty && _location == null && mounted) {
      final fallback = await currentDeviceLocation();
      if (fallback != null && mounted && _location == null) {
        setState(() {
          _location = fallback;
          _locationSource = CaptureLocationSource.device;
        });
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final position = await currentDeviceLocation(requestPermission: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _locating = false;
      if (position != null) {
        _location = position;
        _locationSource = CaptureLocationSource.device;
      }
    });
    if (position == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.captureLocationFailed)),
      );
    }
  }

  Future<void> _editLocation() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute<LatLng>(
        builder: (context) => LocationPickerScreen(initial: _location),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _location = picked;
        _locationSource = CaptureLocationSource.manual;
      });
    }
  }

  Future<void> _submit(
    ProjectSchema schema,
    int projectId,
    int trackerId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final fields = schema
        .fieldsForTracker(trackerId)
        .where(
          (field) => supportedCustomFieldFormats.contains(field.fieldFormat),
        )
        .toList();
    if (_subjectController.text.trim().isEmpty) {
      setState(() => _error = l10n.captureSubjectRequired);
      return;
    }
    final values = normalizeCustomFieldValues(
      fields: fields,
      entered: _customFieldValues,
    );
    final missing = missingRequiredFields(fields: fields, values: values);
    if (missing.isNotEmpty) {
      setState(() => _error = l10n.captureFieldsRequired(missing.join(', ')));
      return;
    }
    final notNumeric = nonNumericFields(fields: fields, values: values);
    if (notNumeric.isNotEmpty) {
      setState(() => _error = l10n.captureFieldsNumeric(notNumeric.join(', ')));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final draft = IssueDraft(
        projectId: projectId,
        trackerId: trackerId,
        subject: _subjectController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _location,
        photos: List.of(_photos),
        customFieldValues: values,
      );
      final defaults = ref.read(captureDefaultsProvider);
      // The queue persists the draft before trying, so from here on nothing
      // the user entered can be lost, online or not.
      final issueId = await ref
          .read(uploadQueueProvider.notifier)
          .submit(draft);
      // Next capture starts from what was just used.
      await defaults.remember(projectId: projectId, trackerId: trackerId);
      if (mounted) {
        ref
          ..invalidate(lastProjectProvider)
          ..invalidate(lastTrackerProvider(projectId));
        final messenger = ScaffoldMessenger.of(context);
        if (issueId != null) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.captureCreated(issueId))),
          );
          context.pushReplacement('/issues/$issueId');
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.captureQueuedOffline)),
          );
          context.go('/home');
        }
      }
    } on StateError {
      // The queue refuses to enqueue without an active session; the guard
      // in build() is about to redirect, so keep the message readable.
      if (mounted) {
        setState(() => _error = l10n.captureNotConnected);
      }
      // The draft survives any failure; only success leaves the screen.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.captureSubmitFailed('$error'));
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
    // Guard: this screen needs a session; state-driven like the rest of the
    // navigation.
    watchSessionEnd(ref, context);
    final issues = ref.watch(issuesProvider).value;
    final projects = issues?.projects ?? const [];
    // Effective selections: defaults are derived, never written during
    // build; state only changes on explicit user action. The last-used
    // project wins over the list head once known.
    final remembered = ref.watch(lastProjectProvider).value;
    final projectId =
        _projectId ??
        (projects.any((project) => project.id == remembered)
            ? remembered
            : (projects.isNotEmpty ? projects.first.id : null));

    if (projectId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.captureTitle)),
        body: Center(child: Text(l10n.captureNoProjects)),
      );
    }

    // Watched once and shared by the body and the controls: two watches of
    // the same provider in one build is duplicated subscription work.
    final schemaState = ref.watch(projectSchemaProvider(projectId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureTitle)),
      body: Column(
        children: [
          CaptureStepHeader(step: _step),
          Expanded(
            child: schemaState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.issuesLoadFailed('$error')),
                ),
              ),
              data: (schema) => _buildStep(l10n, schema, projectId, projects),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          schemaState.maybeWhen(
            data: (schema) => _controls(l10n, schema, projectId),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// The tracker in effect: explicit choice, then the one last used in this
  /// project, then the schema's first.
  int? _effectiveTrackerId(ProjectSchema schema, int projectId) {
    final remembered = ref.watch(lastTrackerProvider(projectId)).value;
    return _trackerId ??
        (schema.trackers.any((tracker) => tracker.id == remembered)
            ? remembered
            : (schema.trackers.isNotEmpty ? schema.trackers.first.id : null));
  }

  Widget _buildStep(
    AppLocalizations l10n,
    ProjectSchema schema,
    int projectId,
    List<BundleProject> projects,
  ) {
    final trackerId = _effectiveTrackerId(schema, projectId);
    final body = switch (_step) {
      CaptureStep.photos => _photosStep(l10n),
      CaptureStep.location => _locationStep(),
      CaptureStep.project => _projectStep(l10n, schema, projects, projectId),
      CaptureStep.details =>
        trackerId == null
            ? Text(l10n.captureNoTrackers)
            : _detailsStep(l10n, schema, trackerId),
      CaptureStep.review => _reviewStep(l10n, schema, projects, projectId),
    };
    return ListView(padding: const EdgeInsets.all(16), children: [body]);
  }

  Widget _photosStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.captureStepPhotosHint),
        const SizedBox(height: 16),
        CapturePhotoStrip(
          photos: _photos,
          onCamera: _submitting ? null : () => _addPhoto(ImageSource.camera),
          onGallery: _submitting ? null : () => _addPhoto(ImageSource.gallery),
          onRemove: _submitting
              ? null
              : (index) => setState(() => _photos.removeAt(index)),
        ),
      ],
    );
  }

  Widget _locationStep() {
    return CaptureLocationCard(
      location: _location,
      source: _locationSource,
      locating: _locating,
      onEdit: _submitting ? null : _editLocation,
      onUseCurrent: _location != null || _submitting || _locating
          ? null
          : _useCurrentLocation,
      onClear: _location == null || _submitting
          ? null
          : () => setState(() {
              _location = null;
              _locationSource = CaptureLocationSource.manual;
            }),
    );
  }

  Widget _projectStep(
    AppLocalizations l10n,
    ProjectSchema schema,
    List<BundleProject> projects,
    int projectId,
  ) {
    final trackerId = _effectiveTrackerId(schema, projectId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: projectId,
          decoration: InputDecoration(
            labelText: l10n.issueProjectLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final project in projects)
              DropdownMenuItem(value: project.id, child: Text(project.name)),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() {
                  _projectId = value;
                  _trackerId = null;
                  _customFieldValues.clear();
                }),
        ),
        const SizedBox(height: 16),
        if (schema.trackers.isEmpty)
          Text(l10n.captureNoTrackers)
        else
          DropdownButtonFormField<int>(
            initialValue: trackerId,
            decoration: InputDecoration(
              labelText: l10n.captureTrackerLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final tracker in schema.trackers)
                DropdownMenuItem(value: tracker.id, child: Text(tracker.name)),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                    _trackerId = value;
                    _customFieldValues.clear();
                  }),
          ),
      ],
    );
  }

  Widget _reviewStep(
    AppLocalizations l10n,
    ProjectSchema schema,
    List<BundleProject> projects,
    int projectId,
  ) {
    final trackerId = _effectiveTrackerId(schema, projectId);
    final project = projects
        .where((candidate) => candidate.id == projectId)
        .map((candidate) => candidate.name)
        .firstOrNull;
    final tracker = schema.trackers
        .where((candidate) => candidate.id == trackerId)
        .map((candidate) => candidate.name)
        .firstOrNull;
    final subject = _subjectController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_photos.isNotEmpty) ...[
          CapturePhotoStrip(photos: _photos),
          const SizedBox(height: 16),
        ],
        _ReviewRow(
          label: l10n.captureSubjectLabel,
          value: subject.isEmpty ? l10n.captureSubjectRequired : subject,
        ),
        if (project != null)
          _ReviewRow(label: l10n.issueProjectLabel, value: project),
        if (tracker != null)
          _ReviewRow(label: l10n.captureTrackerLabel, value: tracker),
        _ReviewRow(
          label: l10n.captureStepLocation,
          value: _location == null
              ? l10n.captureNoLocation
              : '${_location!.latitude.toStringAsFixed(5)}, '
                    '${_location!.longitude.toStringAsFixed(5)}',
        ),
        if (_descriptionController.text.trim().isNotEmpty)
          _ReviewRow(
            label: l10n.captureDescriptionLabel,
            value: _descriptionController.text.trim(),
          ),
      ],
    );
  }

  /// Forward moves a step, or submits on the last one. Nothing blocks
  /// moving on: a step with nothing in it is a legitimate answer (no photo,
  /// no location), and the real validation still runs at submit.
  Widget _controls(AppLocalizations l10n, ProjectSchema schema, int projectId) {
    final isLast = _step == CaptureStep.review;
    return CaptureStepControls(
      busy: _submitting,
      onBack: _step == CaptureStep.photos
          ? null
          : () => setState(() {
              _error = null;
              _step = CaptureStep.values[CaptureStep.values.indexOf(_step) - 1];
            }),
      nextLabel: isLast ? l10n.captureSubmitButton : l10n.captureStepNext,
      onNext: () {
        if (!isLast) {
          setState(() {
            _error = null;
            _step = CaptureStep.values[CaptureStep.values.indexOf(_step) + 1];
          });
          return;
        }
        final trackerId = _effectiveTrackerId(schema, projectId);
        if (trackerId == null) {
          // A project with no tracker cannot receive an issue; saying so
          // beats a Create button that silently does nothing.
          setState(() => _error = l10n.captureNoTrackers);
          return;
        }
        _submit(schema, projectId, trackerId);
      },
    );
  }

  Widget _detailsStep(
    AppLocalizations l10n,
    ProjectSchema schema,
    int trackerId,
  ) {
    final fields = schema
        .fieldsForTracker(trackerId)
        .where(
          (field) => supportedCustomFieldFormats.contains(field.fieldFormat),
        )
        .toList();
    final required = fields.where((field) => field.required).toList();
    final optional = fields.where((field) => !field.required).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _subjectController,
          enabled: !_submitting,
          decoration: InputDecoration(
            labelText: '${l10n.captureSubjectLabel} *',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descriptionController,
          enabled: !_submitting,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.captureDescriptionLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        for (final field in required) ...[
          const SizedBox(height: 16),
          CustomFieldEditor(
            // Keyed per field so text state never leaks across tracker
            // switches when the element tree is otherwise identical.
            key: ValueKey('cf-${field.id}'),
            field: field,
            value: _customFieldValues[field.id],
            onChanged: (value) => setState(() {
              value == null
                  ? _customFieldValues.remove(field.id)
                  : _customFieldValues[field.id] = value;
            }),
          ),
        ],
        if (optional.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () =>
                setState(() => _showOptionalFields = !_showOptionalFields),
            icon: Icon(
              _showOptionalFields ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text(l10n.captureMoreFields),
          ),
          if (_showOptionalFields)
            for (final field in optional) ...[
              const SizedBox(height: 16),
              CustomFieldEditor(
                key: ValueKey('cf-${field.id}'),
                field: field,
                value: _customFieldValues[field.id],
                onChanged: (value) => setState(() {
                  value == null
                      ? _customFieldValues.remove(field.id)
                      : _customFieldValues[field.id] = value;
                }),
              ),
            ],
        ],
      ],
    );
  }
}

/// One labelled line of the review summary.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
