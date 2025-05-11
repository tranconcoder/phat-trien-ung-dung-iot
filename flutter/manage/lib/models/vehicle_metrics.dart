import 'package:google_maps_flutter/google_maps_flutter.dart';

class VehicleMetrics {
  final double speed; // km/h
  final double energy; // percentage (0-100)
  final double energyConsumption; // kWh or L per 100km
  final LatLng location; // GPS coordinates
  final double temperature; // °C
  final double humidity; // %

  VehicleMetrics({
    required this.speed,
    required this.energy,
    required this.energyConsumption,
    required this.location,
    this.temperature = 0,
    this.humidity = 0,
  });

  // Create a copy with updated values
  VehicleMetrics copyWith({
    double? speed,
    double? energy,
    double? energyConsumption,
    LatLng? location,
    double? temperature,
    double? humidity,
  }) {
    return VehicleMetrics(
      speed: speed ?? this.speed,
      energy: energy ?? this.energy,
      energyConsumption: energyConsumption ?? this.energyConsumption,
      location: location ?? this.location,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
    );
  }
}
