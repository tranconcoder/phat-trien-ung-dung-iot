import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import './mqtt_service.dart';
import './location_service.dart';
import '../config/app_config.dart';

class GpsMqttService {
  final LocationService _locationService = LocationService();
  final MqttService _mqttService;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _publishTimer;
  bool _isRunning = false;

  // Constructor
  GpsMqttService({String? clientId}) : _mqttService = MqttService(id: clientId);

  // Initialize both services
  Future<bool> initialize() async {
    try {
      // Initialize location service
      bool locationInitialized = await _locationService.initialize();
      if (!locationInitialized) {
        debugPrint('Failed to initialize location service');
        return false;
      }

      // Connect to MQTT broker
      bool mqttConnected = await _mqttService.connect();
      if (!mqttConnected) {
        debugPrint('Failed to connect to MQTT broker');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error initializing GPS MQTT service: $e');
      return false;
    }
  }

  // Start sending GPS data to MQTT broker
  Future<bool> startSendingGpsData() async {
    if (_isRunning) return true;

    try {
      // Make sure services are initialized
      bool initialized = await initialize();
      if (!initialized) return false;

      // Start location tracking
      bool trackingStarted = await _locationService.startTracking();
      if (!trackingStarted) {
        debugPrint('Failed to start location tracking');
        return false;
      }

      // Listen to location updates
      _locationSubscription =
          _locationService.locationStream.listen((position) {
        // This just receives the updates, but we'll publish on a timer
        // for more controlled frequency
      });

      // Set up timer to publish at regular intervals
      _publishTimer = Timer.periodic(
          const Duration(milliseconds: AppConfig.LOCATION_UPDATE_INTERVAL),
          (_) => _publishGpsData());

      _isRunning = true;
      return true;
    } catch (e) {
      debugPrint('Error starting GPS MQTT service: $e');
      return false;
    }
  }

  // Publish GPS data to MQTT
  Future<void> _publishGpsData() async {
    try {
      Position? position = _locationService.lastKnownPosition;

      // If we don't have a position yet, try to get one
      position ??= await _locationService.getLocation();

      // If we still don't have a position, skip this update
      if (position == null) {
        debugPrint('No position available to publish');
        return;
      }

      // Send GPS data to MQTT broker
      _mqttService.publishLocationData(position.latitude, position.longitude,
          speed: position.speed, heading: position.heading);

      debugPrint(
          'Published GPS data: Lat: ${position.latitude}, Lng: ${position.longitude}');
    } catch (e) {
      debugPrint('Error publishing GPS data: $e');
    }
  }

  // Stop sending GPS data
  Future<void> stop() async {
    _isRunning = false;

    // Cancel timer
    _publishTimer?.cancel();
    _publishTimer = null;

    // Cancel location subscription
    await _locationSubscription?.cancel();
    _locationSubscription = null;

    // Stop location tracking
    await _locationService.stopTracking();

    // Disconnect MQTT client
    _mqttService.disconnect();
  }

  // Dispose resources
  void dispose() {
    stop();
    _locationService.dispose();
  }

  // Status getters
  bool get isRunning => _isRunning;
  bool get isMqttConnected => _mqttService.isConnected;
  Stream<bool> get mqttConnectionStatusStream =>
      _mqttService.connectionStatusStream;
}
