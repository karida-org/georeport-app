import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../map/offline_regions.dart';

/// Map-related controls in one panel, opened from the button beside the
/// filter row: offline area download and stored-area management. Keeps the
/// map itself free of floating chrome (the old debug download button sat on
/// top of the attribution).
Future<void> showMapControlsSheet(
  BuildContext context, {
  required MapController controller,
  required String styleUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) =>
        _MapControlsSheet(controller: controller, styleUrl: styleUrl),
  );
}

class _MapControlsSheet extends StatefulWidget {
  const _MapControlsSheet({required this.controller, required this.styleUrl});

  final MapController controller;
  final String styleUrl;

  @override
  State<_MapControlsSheet> createState() => _MapControlsSheetState();
}

class _MapControlsSheetState extends State<_MapControlsSheet> {
  bool _downloading = false;
  int? _storedRegions;

  @override
  void initState() {
    super.initState();
    _refreshStoredCount();
  }

  Future<void> _refreshStoredCount() async {
    try {
      final count = await storedRegionCount();
      if (mounted) {
        setState(() => _storedRegions = count);
      }
      // Fired from initState without an awaiter: a failure must not become
      // an unhandled async error. No count just leaves the row disabled.
    } on Exception catch (error) {
      debugPrint('Stored region count unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stored = _storedRegions;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: _downloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_for_offline_outlined),
            title: Text(l10n.mapDownloadArea),
            subtitle: Text(l10n.mapDownloadAreaHint),
            enabled: !_downloading,
            onTap: _download,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.mapRemoveStoredAreas),
            subtitle: stored == null ? null : Text(l10n.mapStoredAreas(stored)),
            enabled: stored != null && stored > 0,
            onTap: _removeAll,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);
    try {
      final result = await downloadCurrentRegion(
        controller: widget.controller,
        styleUrl: widget.styleUrl,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.mapDownloadDone(
              result.tiles,
              result.megabytes.toStringAsFixed(1),
            ),
          ),
        ),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mapDownloadFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _refreshStoredCount();
      }
    }
  }

  Future<void> _removeAll() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await removeStoredRegions();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mapRemoveStoredAreasDone)),
    );
    await _refreshStoredCount();
  }
}
