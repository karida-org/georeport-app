import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/issue_document.dart';
import '../../../widgets/authed_image.dart';

/// Attachments with inline thumbnails for images; every entry lists name
/// and size. Thumbnails ride the authenticated client, not plain HTTP.
class AttachmentsSection extends StatelessWidget {
  const AttachmentsSection({required this.attachments, super.key});

  final List<AttachmentInfo> attachments;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final images = attachments
        .where((attachment) => attachment.isImage)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.issueAttachmentsHeading, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (images.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = images[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AuthedImage(
                    urlOrPath: image.thumbnailUrl ?? image.url,
                    width: 96,
                    height: 96,
                  ),
                );
              },
            ),
          ),
        for (final attachment in attachments)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(attachment.isImage ? Icons.image : Icons.attach_file),
            title: Text(attachment.filename),
            subtitle: attachment.filesize == null
                ? null
                : Text(_formatSize(attachment.filesize!)),
          ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
