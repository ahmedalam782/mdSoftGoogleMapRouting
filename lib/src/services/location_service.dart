import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class LocationService {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;

  Future<void> _configureSettings({required bool highAccuracy}) async {
    await _location.changeSettings(
      accuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.low,
      distanceFilter: highAccuracy ? 2 : 100000,
      interval: highAccuracy ? 1000 : 3600000,
    );
  }

  Future<void> checkAndRequestLocationService() async {
    try {
      bool isServiceEnabled = await _location.serviceEnabled();
      if (!isServiceEnabled) {
        isServiceEnabled = await _location.requestService();
        if (!isServiceEnabled) {
          throw LocationServiceException();
        }
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
      var permission = await _location.hasPermission();
      if (permission == PermissionStatus.deniedForever) {
        throw LocationPermissionException();
      }
      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
      }
      if (permission != PermissionStatus.granted &&
          permission != PermissionStatus.grantedLimited) {
        throw LocationPermissionException();
      }
    } on LocationPermissionException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint("Permission check failed: ${e.message}");
      throw LocationPermissionException();
    }
  }

  void getRealTimeLocationData(void Function(LocationData)? onData) async {
    try {
      await checkAndRequestLocationService();
      await checkAndRequestLocationPermission();
      await _configureSettings(highAccuracy: true);
      await _locationSubscription?.cancel();
      _locationSubscription = _location.onLocationChanged.listen(onData);
    } on PlatformException catch (e) {
      debugPrint("Real-time location failed: ${e.message}");
      rethrow;
    }
  }

  Future<LocationData> getLocation() async {
    try {
      await checkAndRequestLocationService();
      await checkAndRequestLocationPermission();
      await _configureSettings(highAccuracy: true);
      return await _location.getLocation();
    } on PlatformException catch (e) {
      debugPrint("Get location failed: ${e.message}");
      rethrow;
    }
  }

  void stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  Future<StreamSubscription<LocationData>?> getLocationStream(
      void Function(LocationData)? onData) async {
    try {
      await checkAndRequestLocationService();
      await checkAndRequestLocationPermission();
      await _configureSettings(highAccuracy: true);
      await _locationSubscription?.cancel();
      _locationSubscription = _location.onLocationChanged.listen(onData);
      return _locationSubscription;
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

enum DistanceUnit { meters, kilometers, miles }
