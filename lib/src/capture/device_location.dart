import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Fetches the device position, or null when permission is missing or no fix
/// arrives in time. With [requestPermission] false an undecided permission is
/// treated as unavailable, so no dialog ever interrupts the calling flow.
Future<LatLng?> currentDeviceLocation({
  bool requestPermission = false,
  Duration timeLimit = const Duration(seconds: 15),
}) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(timeLimit: timeLimit),
    );
    return LatLng(position.latitude, position.longitude);
  } on Exception {
    return null;
  }
}
