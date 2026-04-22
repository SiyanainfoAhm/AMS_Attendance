import "dart:async";

import "package:geolocator/geolocator.dart";

class LocationResult {
  final double latitude;
  final double longitude;
  final double? accuracyM;

  LocationResult({required this.latitude, required this.longitude, required this.accuracyM});
}

class LocationService {
  Future<LocationResult> getCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError("Location services are disabled.");
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw StateError("Location permission denied.");
    }
    if (perm == LocationPermission.deniedForever) {
      throw StateError("Location permission denied forever. Enable it in settings.");
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LocationResult(latitude: pos.latitude, longitude: pos.longitude, accuracyM: pos.accuracy);
  }

  double distanceM({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
  }
}

