import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class LocationService {
  StreamSubscription<Position>? _locationSubscription;

  LocationSettings _locationSettings({required bool highAccuracy}) {
    final accuracy =
        highAccuracy ? LocationAccuracy.high : LocationAccuracy.low;
    final distanceFilter = highAccuracy ? 2 : 100000;

    if (kIsWeb) {
      return LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
          intervalDuration: highAccuracy
              ? const Duration(seconds: 1)
              : const Duration(hours: 1),
          foregroundNotificationConfig: highAccuracy
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'Route tracking',
                  notificationText: 'Tracking your route in the background',
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: accuracy,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: distanceFilter,
          pauseLocationUpdatesAutomatically: !highAccuracy,
          showBackgroundLocationIndicator: highAccuracy,
          allowBackgroundLocationUpdates: highAccuracy,
        );
      default:
        return LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
        );
    }
  }

  Future<void> checkAndRequestLocationService() async {
    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        throw LocationServiceException();
      }
    } on LocationServiceException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint("Location service check failed: ${e.message}");
      throw LocationServiceException();
    }
  }

  Future<void> checkAndRequestLocationPermission() async {
    try {
      if (kIsWeb) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        throw LocationPermissionException();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw LocationPermissionException();
      }
    } on LocationPermissionException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint("Permission check failed: ${e.message}");
      throw LocationPermissionException();
    }
  }

  void getRealTimeLocationData(void Function(Position)? onData) async {
    try {
      await checkAndRequestLocationService();
      await checkAndRequestLocationPermission();
      await _locationSubscription?.cancel();
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: _locationSettings(highAccuracy: true),
      ).listen(onData);
    } on LocationServiceDisabledException {
      throw LocationServiceException();
    } on PermissionDeniedException {
      throw LocationPermissionException();
    } on PlatformException catch (e) {
      debugPrint("Real-time location failed: ${e.message}");
      rethrow;
    }
  }

  Future<Position> getLocation() async {
    try {
      await checkAndRequestLocationService();
      await checkAndRequestLocationPermission();
      return await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings(highAccuracy: true),
      );
    } on LocationServiceDisabledException {
      throw LocationServiceException();
    } on PermissionDeniedException {
      throw LocationPermissionException();
    } on PlatformException catch (e) {
      debugPrint("Get location failed: ${e.message}");
      rethrow;
    }
  }

  void stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  Future<StreamSubscription<Position>?> getLocationStream(
      void Function(Position)? onData) async {
    try {
      await checkAndRequestLocationService();
      await checkAndRequestLocationPermission();
      await _locationSubscription?.cancel();
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: _locationSettings(highAccuracy: true),
      ).listen(onData);
      return _locationSubscription;
    } on LocationServiceDisabledException {
      throw LocationServiceException();
    } on PermissionDeniedException {
      throw LocationPermissionException();
    } on PlatformException catch (e) {
      debugPrint("Get location stream failed: ${e.message}");
      rethrow;
    }
  }

  static const double _earthRadiusKm = 6371.0;
  static const double _metersInKm = 1000.0;
  static const double _milesInKm = 0.621371;

  static double degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  static double distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    DistanceUnit unit,
  ) {
    if (lat1.abs() > 90 || lat2.abs() > 90) {
      throw ArgumentError('Invalid latitude value');
    }
    if (lon1.abs() > 180 || lon2.abs() > 180) {
      throw ArgumentError('Invalid longitude value');
    }

    final lat1Rad = degreesToRadians(lat1);
    final lon1Rad = degreesToRadians(lon1);
    final lat2Rad = degreesToRadians(lat2);
    final lon2Rad = degreesToRadians(lon2);

    final dLat = lat2Rad - lat1Rad;
    final dLon = lon2Rad - lon1Rad;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    final distanceInKm = _earthRadiusKm * c;

    switch (unit) {
      case DistanceUnit.meters:
        return distanceInKm * _metersInKm;
      case DistanceUnit.kilometers:
        return distanceInKm;
      case DistanceUnit.miles:
        return distanceInKm * _milesInKm;
    }
  }

  bool isAtDestination(LatLng current, LatLng destination,
      {double toleranceMeters = 8.0}) {
    final distance = distanceBetween(
      current.latitude,
      current.longitude,
      destination.latitude,
      destination.longitude,
      DistanceUnit.meters,
    );
    return distance <= toleranceMeters;
  }
}

class LocationServiceException implements Exception {}

class LocationPermissionException implements Exception {}

double degreesToRadians(double degrees) {
  return degrees * pi / 180;
}

enum DistanceUnit { meters, kilometers, miles }
