import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:quan_ly_giao_thong/models/vehicle_metrics.dart';
import 'package:quan_ly_giao_thong/services/mqtt_service.dart';

class VehicleTrackingScreen extends StatefulWidget {
  const VehicleTrackingScreen({super.key});

  @override
  State<VehicleTrackingScreen> createState() => _VehicleTrackingScreenState();
}

class _VehicleTrackingScreenState extends State<VehicleTrackingScreen> {
  final MqttService _mqttService = MqttService();
  final Completer<GoogleMapController> _mapController = Completer();
  late StreamSubscription<VehicleMetrics> _metricsSubscription;
  late VehicleMetrics _metrics;
  Set<Marker> _markers = {};

  // Connection state
  MqttConnectionState _connectionState = MqttConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _metrics = _mqttService.currentMetrics;

    // Update markers with initial metrics
    _updateMapMarker(_metrics);

    // Listen for connection state changes
    _mqttService.connectionStateStream.listen((state) {
      setState(() {
        _connectionState = state;
      });
    });

    // Listen for metrics updates
    _metricsSubscription = _mqttService.metricsStream.listen((metrics) {
      setState(() {
        _metrics = metrics;
        _updateMapMarker(metrics);
      });
    });

    // If not already connected, connect to MQTT broker
    if (_mqttService.connectionState != MqttConnectionState.connected) {
      _connectToMqttBroker();
    }
  }

  void _updateMapMarker(VehicleMetrics metrics) {
    final marker = Marker(
      markerId: const MarkerId('vehicle'),
      position: metrics.location,
      infoWindow: InfoWindow(
        title: 'Current Vehicle',
        snippet: 'Speed: ${metrics.speed.toStringAsFixed(1)} km/h',
      ),
    );

    setState(() {
      _markers = {marker};
    });

    // Move camera to follow vehicle
    if (_mapController.isCompleted) {
      _mapController.future.then((controller) {
        controller.animateCamera(CameraUpdate.newLatLng(metrics.location));
      });
    }
  }

  void _connectToMqttBroker() {
    _mqttService
        .connect(
          host: 'fd66ecb3.ala.asia-southeast1.emqxsl.com',
          port: 8883,
          clientId: 'flutter_tracking_${DateTime.now().millisecondsSinceEpoch}',
          useTLS: true,
          // Add username/password if required
          // username: 'username',
          // password: 'password',
        )
        .then((success) {
          if (success) {
            _mqttService.subscribeToVehicleMetrics('vehicle1');
          } else {
            if (kDebugMode) {
              print('Failed to connect to MQTT broker from tracking screen');
            }
          }
        });
  }

  @override
  void dispose() {
    _metricsSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Tracking'),
        actions: [_buildConnectionStatusIcon()],
      ),
      body: Column(
        children: [
          // Map view
          Expanded(
            flex: 3,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _metrics.location,
                zoom: 15,
              ),
              markers: _markers,
              myLocationEnabled: true,
              mapType: MapType.normal,
              onMapCreated: (GoogleMapController controller) {
                _mapController.complete(controller);
              },
            ),
          ),

          // Metrics dashboard
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Vehicle Metrics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricCard(
                      label: 'Speed',
                      value: '${_metrics.speed.toStringAsFixed(1)} km/h',
                      icon: Icons.speed,
                      color: Colors.blue,
                    ),
                    _buildMetricCard(
                      label: 'Energy',
                      value: '${_metrics.energy.toStringAsFixed(1)}%',
                      icon: Icons.battery_charging_full,
                      color: _getEnergyColor(_metrics.energy),
                    ),
                    _buildMetricCard(
                      label: 'Consumption',
                      value:
                          '${_metrics.energyConsumption.toStringAsFixed(1)}/100km',
                      icon: Icons.local_gas_station,
                      color: Colors.purple,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Current Location: ${_metrics.location.latitude.toStringAsFixed(6)}, ${_metrics.location.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusIcon() {
    IconData icon;
    Color color;

    switch (_connectionState) {
      case MqttConnectionState.connected:
        icon = Icons.cloud_done;
        color = Colors.green;
        break;
      case MqttConnectionState.connecting:
        icon = Icons.cloud_upload;
        color = Colors.orange;
        break;
      case MqttConnectionState.disconnected:
        icon = Icons.cloud_off;
        color = Colors.grey;
        break;
      case MqttConnectionState.error:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade100,
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getEnergyColor(double energy) {
    if (energy > 50) return Colors.green;
    if (energy > 20) return Colors.orange;
    return Colors.red;
  }
}
