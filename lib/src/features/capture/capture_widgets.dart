import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../capture/issue_draft.dart';

/// Where the suggested location came from, so the card can say so.
enum CaptureLocationSource { manual, exif, device }

class CapturePhotoStrip extends StatelessWidget {
  const CapturePhotoStrip({
    super.key,
    required this.photos,
    this.onCamera,
    this.onGallery,
    this.onRemove,
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
        // Read-only (the review step passes no handlers): show the photos
        // without offering actions that would take the user back a step.
        if (onCamera != null || onGallery != null)
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

class CaptureLocationCard extends StatelessWidget {
  const CaptureLocationCard({
    super.key,
    required this.location,
    required this.source,
    required this.locating,
    required this.onEdit,
    required this.onUseCurrent,
    required this.onClear,
  });

  final LatLng? location;
  final CaptureLocationSource source;
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
      (_, CaptureLocationSource.exif) => Text(l10n.captureLocationFromPhoto),
      (_, CaptureLocationSource.device) => Text(l10n.captureLocationFromDevice),
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
