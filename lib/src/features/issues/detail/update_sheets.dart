import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/issue_document.dart';
import '../../../capture/issue_draft.dart';
import '../../../media/mime.dart';
import '../issue_update.dart';

/// Moves an issue to one of the statuses the editing contract allows, with
/// an optional comment riding the same update.
Future<void> showStatusUpdateSheet(
  BuildContext context, {
  required IssueDocument issue,
  required NamedRef target,
}) {
  return _showUpdateSheet(
    context,
    issue: issue,
    statusTarget: target,
    allowPhotos: false,
  );
}

/// Adds a comment, optionally with photos, honoring can_add_attachments.
Future<void> showCommentSheet(
  BuildContext context, {
  required IssueDocument issue,
}) {
  return _showUpdateSheet(
    context,
    issue: issue,
    statusTarget: null,
    allowPhotos: issue.editable.canAddAttachments,
  );
}

Future<void> _showUpdateSheet(
  BuildContext context, {
  required IssueDocument issue,
  required NamedRef? statusTarget,
  required bool allowPhotos,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _UpdateSheet(
        issue: issue,
        statusTarget: statusTarget,
        allowPhotos: allowPhotos,
      ),
    ),
  );
}

class _UpdateSheet extends ConsumerStatefulWidget {
  const _UpdateSheet({
    required this.issue,
    required this.statusTarget,
    required this.allowPhotos,
  });

  final IssueDocument issue;

  /// Non-null for a status change; null for a plain comment.
  final NamedRef? statusTarget;
  final bool allowPhotos;

  @override
  ConsumerState<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<_UpdateSheet> {
  final _note = TextEditingController();
  final _picker = ImagePicker();
  final List<DraftPhoto> _photos = [];
  bool _submitting = false;
  String? _error;

  bool get _isStatusChange => widget.statusTarget != null;

  @override
  void dispose() {
    _note.dispose();
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
        if (!mounted) {
          return;
        }
        setState(() {
          _photos.add(
            DraftPhoto(
              filename: image.name,
              bytes: bytes,
              contentType: image.mimeType ?? mimeForFilename(image.name),
            ),
          );
        });
      }
      // Camera unavailable, permission denied, unreadable file: platform
      // exceptions here are user-visible situations.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.capturePhotoAddFailed('$error'));
      }
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_isStatusChange && _note.text.trim().isEmpty && _photos.isEmpty) {
      setState(() => _error = l10n.issueCommentEmpty);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(issueUpdaterProvider)
          .submit(
            issueId: widget.issue.id,
            lockVersion: widget.issue.lockVersion,
            statusId: widget.statusTarget?.id,
            notes: _note.text,
            photos: List.of(_photos),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.issueUpdated)));
        Navigator.pop(context);
      }
    } on StaleIssueException {
      if (mounted) {
        setState(() => _error = l10n.issueConflictBody);
      }
      // Validation failures and connectivity both land here; the sheet
      // stays open so nothing typed is lost.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.issueUpdateFailed('$error'));
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isStatusChange
                ? l10n.issueStatusSheetTitle(widget.statusTarget!.name)
                : l10n.issueAddCommentButton,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            enabled: !_submitting,
            maxLines: 3,
            autofocus: !_isStatusChange,
            decoration: InputDecoration(
              labelText: _isStatusChange
                  ? l10n.issueNoteOptionalLabel
                  : l10n.issueCommentLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.allowPhotos) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_camera),
                  tooltip: l10n.capturePhotoCamera,
                  onPressed: _submitting
                      ? null
                      : () => _addPhoto(ImageSource.camera),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library),
                  tooltip: l10n.capturePhotoGallery,
                  onPressed: _submitting
                      ? null
                      : () => _addPhoto(ImageSource.gallery),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 6),
                      itemBuilder: (context, index) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              _photos[index].bytes,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton(
                              icon: const Icon(Icons.cancel, size: 16),
                              tooltip: l10n.capturePhotoRemove(index + 1),
                              onPressed: _submitting
                                  ? null
                                  : () =>
                                        setState(() => _photos.removeAt(index)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isStatusChange
                        ? l10n.issueUpdateSubmit
                        : l10n.issueCommentSubmit,
                  ),
          ),
        ],
      ),
    );
  }
}
