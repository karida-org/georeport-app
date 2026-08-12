import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/project_schema.dart';
import '../../capture/device_location.dart';
import '../../capture/exif_location.dart';
import '../../capture/issue_draft.dart';
import '../../connections/connection_manager.dart';
import '../issues/issues_store.dart';
import 'capture_defaults.dart';
import 'capture_providers.dart';
import 'custom_field_editor.dart';
import 'location_picker_screen.dart';

/// MIME types by photo file extension; unknown extensions send no type.
const _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// Where a draft location came from, shown as context under the coordinates.
enum _LocationSource { manual, exif, device }

/// The capture flow: photos first, then a minimal schema-driven form.
/// Required fields surface automatically; everything optional folds away.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

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
  _LocationSource _locationSource = _LocationSource.manual;
  bool _locating = false;
  bool _showOptionalFields = false;
  final Map<int, Object> _customFieldValues = {};
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final images = source == ImageSource.gallery
          ? await _picker.pickMultiImage()
          : [await _picker.pickImage(source: source)].nonNulls.toList();
      for (final image in images) {
        final bytes = await image.readAsBytes();
        final extension = image.name.split('.').last.toLowerCase();
        if (!mounted) {
          return;
        }
        setState(() {
          _photos.add(
            DraftPhoto(
              filename: image.name,
              bytes: bytes,
              contentType: image.mimeType ?? _mimeByExtension[extension],
            ),
          );
        });
        // First geotagged photo wins the location suggestion; the user can
        // still adjust or clear it.
        if (_location == null) {
          final suggested = await exifLocationOf(bytes);
          if (suggested != null && mounted) {
            setState(() {
              _location = suggested;
              _locationSource = _LocationSource.exif;
            });
          }
        }
      }
      // No EXIF position on any photo: fall back to where the user stands,
      // but only when location permission is already granted; a permission
      // dialog must never interrupt the photo flow uninvited.
      if (images.isNotEmpty && _location == null && mounted) {
        final fallback = await currentDeviceLocation();
        if (fallback != null && mounted && _location == null) {
          setState(() {
            _location = fallback;
            _locationSource = _LocationSource.device;
          });
        }
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
        _locationSource = _LocationSource.device;
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
        _locationSource = _LocationSource.manual;
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
    // A never-touched switch means "off", not "missing".
    final values = <int, Object>{
      for (final field in fields)
        if (field.fieldFormat == 'bool' && field.required)
          field.id: _customFieldValues[field.id] ?? '0',
    };
    // Trim text values so whitespace never masquerades as content: an
    // all-blank entry drops out entirely and fails the required check.
    for (final entry in _customFieldValues.entries) {
      final value = entry.value;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          values[entry.key] = trimmed;
        }
      } else {
        values[entry.key] = value;
      }
    }
    final missing = [
      for (final field in fields)
        if (field.required && values[field.id] == null) field.name,
    ];
    if (missing.isNotEmpty) {
      setState(() => _error = l10n.captureFieldsRequired(missing.join(', ')));
      return;
    }
    final notNumeric = [
      for (final field in fields)
        if ((field.fieldFormat == 'int' || field.fieldFormat == 'float') &&
            values[field.id] is String &&
            (field.fieldFormat == 'int'
                    ? int.tryParse(values[field.id]! as String)
                    : num.tryParse(values[field.id]! as String)) ==
                null)
          field.name,
    ];
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
      final issueId = await ref.read(submitDraftProvider)(draft);
      // Next capture starts from what was just used.
      await defaults.remember(projectId: projectId, trackerId: trackerId);
      if (mounted) {
        ref
          ..invalidate(lastProjectProvider)
          ..invalidate(lastTrackerProvider(projectId))
          ..invalidate(issuesProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.captureCreated(issueId))));
        context.go('/issues/$issueId');
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
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value != null && next.value!.active == null && mounted) {
        context.go('/');
      }
    });
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureTitle)),
      body: projectId == null
          ? Center(child: Text(l10n.captureNoProjects))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PhotoStrip(
                  photos: _photos,
                  onCamera: _submitting
                      ? null
                      : () => _addPhoto(ImageSource.camera),
                  onGallery: _submitting
                      ? null
                      : () => _addPhoto(ImageSource.gallery),
                  onRemove: _submitting
                      ? null
                      : (index) => setState(() => _photos.removeAt(index)),
                ),
                const SizedBox(height: 16),
                _LocationCard(
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
                          _locationSource = _LocationSource.manual;
                        }),
                ),
                const SizedBox(height: 16),
                if (projects.length > 1) ...[
                  DropdownButtonFormField<int>(
                    initialValue: projectId,
                    decoration: InputDecoration(
                      labelText: l10n.issueProjectLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final project in projects)
                        DropdownMenuItem(
                          value: project.id,
                          child: Text(project.name),
                        ),
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
                ],
                ref
                    .watch(projectSchemaProvider(projectId))
                    .when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (error, _) =>
                          Text(l10n.issuesLoadFailed('$error')),
                      data: (schema) => _buildForm(l10n, schema, projectId),
                    ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildForm(
    AppLocalizations l10n,
    ProjectSchema schema,
    int projectId,
  ) {
    // Same derivation as the project: explicit choice, then the tracker
    // last used in this project, then the schema's first tracker.
    final remembered = ref.watch(lastTrackerProvider(projectId)).value;
    final trackerId =
        _trackerId ??
        (schema.trackers.any((tracker) => tracker.id == remembered)
            ? remembered
            : (schema.trackers.isNotEmpty ? schema.trackers.first.id : null));
    if (trackerId == null) {
      return Text(l10n.captureNoTrackers);
    }
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
        const SizedBox(height: 16),
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
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting
              ? null
              : () => _submit(schema, projectId, trackerId),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.captureSubmitButton),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final List<DraftPhoto> photos;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photos.isNotEmpty) ...[
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      photos[index].bytes,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      // Thumbnails never need native resolution.
                      cacheWidth: 192,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, size: 20),
                      tooltip: l10n.capturePhotoRemove(index + 1),
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black38,
                        minimumSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: onRemove == null
                          ? null
                          : () => onRemove!(index),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera),
                label: Text(l10n.capturePhotoCamera),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library),
                label: Text(l10n.capturePhotoGallery),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.location,
    required this.source,
    required this.locating,
    required this.onEdit,
    required this.onUseCurrent,
    required this.onClear,
  });

  final LatLng? location;
  final _LocationSource source;
  final bool locating;
  final VoidCallback? onEdit;
  final VoidCallback? onUseCurrent;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = this.location;
    final subtitle = switch ((location, source)) {
      (null, _) => Text(l10n.captureNoLocationHint),
      (_, _LocationSource.exif) => Text(l10n.captureLocationFromPhoto),
      (_, _LocationSource.device) => Text(l10n.captureLocationFromDevice),
      _ => null,
    };
    return Card(
      child: ListTile(
        leading: Icon(
          location == null ? Icons.location_off : Icons.place,
          color: location == null
              ? Theme.of(context).colorScheme.outline
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          location == null
              ? l10n.captureNoLocation
              : '${location.latitude.toStringAsFixed(5)}, '
                    '${location.longitude.toStringAsFixed(5)}',
        ),
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (location == null)
              IconButton(
                icon: locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                tooltip: l10n.captureUseCurrentLocation,
                onPressed: onUseCurrent,
              ),
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l10n.captureClearLocation,
                onPressed: onClear,
              ),
            IconButton(
              icon: const Icon(Icons.edit_location_alt),
              tooltip: l10n.captureEditLocation,
              onPressed: onEdit,
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
