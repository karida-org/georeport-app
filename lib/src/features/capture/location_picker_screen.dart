import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' hide Position;

import '../../../l10n/generated/app_localizations.dart';

const _styleUrl = String.fromEnvironment(
  'GEOREPORT_MAP_STYLE',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

/// Full-screen location chooser: the pin stays centered, the map moves under
/// it. Returns the chosen position, or null when dismissed.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({this.initial, super.key});

  final LatLng? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  MapController? _controller;
  bool _locating = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final initial = widget.initial;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureLocationTitle)),
      body: Stack(
        children: [
          MapLibreMap(
            options: MapOptions(
              initStyle: _styleUrl,
              initCenter: Geographic(
                lon: initial?.longitude ?? 137.0,
                lat: initial?.latitude ?? 37.0,
              ),
              initZoom: initial == null ? 3 : 16,
            ),
            onMapCreated: (controller) => _controller = controller,
            children: const [SourceAttribution()],
          ),
          // The fixed crosshair pin; its tip points at the map center.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(Icons.place, size: 40, color: Color(0xFF00695C)),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 96,
            child: IconButton.filledTonal(
              icon: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              tooltip: l10n.captureUseCurrentLocation,
              onPressed: _locating ? null : _moveToCurrentLocation,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              final camera = _controller?.getCamera();
              if (camera == null) {
                return;
              }
              Navigator.pop(
                context,
                LatLng(
                  camera.center.lat.toDouble(),
                  camera.center.lon.toDouble(),
                ),
              );
            },
            child: Text(l10n.captureUseThisLocation),
          ),
        ),
      ),
    );
  }

  Future<void> _moveToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      await _controller?.moveCamera(
        center: Geographic(lon: position.longitude, lat: position.latitude),
        zoom: 16,
      );
    } on Exception {
      // Location is a convenience; the user can still pan manually.
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }
}
