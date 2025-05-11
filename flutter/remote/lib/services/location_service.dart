import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';

class LocationService {
  StreamSubscription<Position>? _locationSubscription;
  final StreamController<Position> _locationController =
      StreamController<Position>.broadcast();
  Stream<Position> get locationStream => _locationController.stream;

  // Flag to track if service is running
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // Last known position
  Position? _lastKnownPosition;
  Position? get lastKnownPosition => _lastKnownPosition;

  // Initialize and request permissions
  Future<bool> initialize() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Request user to enable location services
        serviceEnabled = await Geolocator.openLocationSettings();
        if (!serviceEnabled) {
          debugPrint('Location services are disabled');
          return false;
        }
      }

      // Request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // The user has permanently denied location permissions
        debugPrint('Location permissions are permanently denied');

        // Try to open app settings for manual permission granting
        await openAppSettings();
        return false;
      }

      // Try to get the current position
      try {
        _lastKnownPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
      } catch (e) {
        debugPrint('Error getting current position: $e');
        // Continue anyway as we'll start tracking
      }

      return true;
    } catch (e) {
      debugPrint('Error initializing location service: $e');
      return false;
    }
  }

  // Start tracking location
  Future<bool> startTracking() async {
    if (_isRunning) return true;

    bool initialized = await initialize();
    if (!initialized) return false;

    try {
      // Set up location tracking
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: AppConfig.LOCATION_DISTANCE_FILTER.toInt(),
          timeLimit:
              const Duration(seconds: 10), // Timeout if no location in 10 sec
        ),
      ).listen(
        (Position position) {
          _lastKnownPosition = position;
          _locationController.add(position);
          debugPrint(
              'Location update: Lat: ${position.latitude}, Lng: ${position.longitude}');
        },
        onError: (e) {
          debugPrint('Error from location stream: $e');
          // Restart tracking if there's an error
          stopTracking().then((_) => startTracking());
        },
      );

      _isRunning = true;
      return true;
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
      return false;
    }
  }

  // Stop tracking location
  Future<void> stopTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _isRunning = false;
  }

  // Dispose resources
  void dispose() {
    stopTracking();
    _locationController.close();
  }

  // Get last known location or request a new one
  Future<Position?> getLocation() async {
    if (_lastKnownPosition != null) {
      return _lastKnownPosition;
    }

    try {
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }
}
