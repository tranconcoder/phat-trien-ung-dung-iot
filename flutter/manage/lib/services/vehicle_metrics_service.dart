import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:quan_ly_giao_thong/models/vehicle_metrics.dart';

class VehicleMetricsService {
  // Singleton pattern
  static final VehicleMetricsService _instance =
      VehicleMetricsService._internal();
  factory VehicleMetricsService() => _instance;
  VehicleMetricsService._internal();

  // Default initial values
  final _random = Random();

  // Initial metrics with default values
  VehicleMetrics _currentMetrics = VehicleMetrics(
    speed: 0,
    energy: 80,
    energyConsumption: 5.5,
    location: const LatLng(10.823099, 106.629662), // Ho Chi Minh City
    temperature: 25.0, // Default temperature
    humidity: 60.0, // Default humidity
  );

  // Stream controller for metrics updates
  final _metricsController = StreamController<VehicleMetrics>.broadcast();
  Stream<VehicleMetrics> get metricsStream => _metricsController.stream;

  // Timer for simulating updates
  Timer? _updateTimer;

  // Get current metrics
  VehicleMetrics get currentMetrics => _currentMetrics;

  // Start simulating metrics updates
  void startSimulation() {
    if (_updateTimer != null) {
      _updateTimer!.cancel();
    }

    // Update metrics every second
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _simulateMetricsUpdate();
    });
  }

  // Stop simulation
  void stopSimulation() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  // Simulate metrics update
  void _simulateMetricsUpdate() {
    // Simulate speed changes (0-120 km/h)
    double newSpeed = _currentMetrics.speed + (_random.nextDouble() * 6 - 3);
    newSpeed = max(0, min(120, newSpeed));

    // Simulate energy consumption (gradually decreasing)
    double newEnergy = _currentMetrics.energy - (_random.nextDouble() * 0.3);
    newEnergy = max(0, min(100, newEnergy));

    // Simulate consumption changes (4-8 units per 100km)
    double newConsumption =
        _currentMetrics.energyConsumption + (_random.nextDouble() * 0.4 - 0.2);
    newConsumption = max(4, min(8, newConsumption));

    // Simulate location changes (small movements)
    double latOffset = (_random.nextDouble() * 0.0002 - 0.0001);
    double lngOffset = (_random.nextDouble() * 0.0002 - 0.0001);
    LatLng newLocation = LatLng(
      _currentMetrics.location.latitude + latOffset,
      _currentMetrics.location.longitude + lngOffset,
    );

    // Simulate temperature changes (20-35°C with slow variations)
    double newTemperature =
        _currentMetrics.temperature + (_random.nextDouble() * 0.4 - 0.2);
    newTemperature = max(20, min(35, newTemperature));

    // Simulate humidity changes (40-80% with slow variations)
    double newHumidity =
        _currentMetrics.humidity + (_random.nextDouble() * 2 - 1);
    newHumidity = max(40, min(80, newHumidity));

    // Update metrics
    _currentMetrics = VehicleMetrics(
      speed: newSpeed,
      energy: newEnergy,
      energyConsumption: newConsumption,
      location: newLocation,
      temperature: newTemperature,
      humidity: newHumidity,
    );

    // Broadcast update
    _metricsController.add(_currentMetrics);
  }

  // Set current location manually
  void setLocation(LatLng location) {
    _currentMetrics = _currentMetrics.copyWith(location: location);
    _metricsController.add(_currentMetrics);
  }

  // Clean up
  void dispose() {
    _updateTimer?.cancel();
    _metricsController.close();
  }
}
