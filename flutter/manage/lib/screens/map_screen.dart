import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/mqtt_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final LatLng _defaultLocation = LatLng(
    AppConfig.DEFAULT_LATITUDE,
    AppConfig.DEFAULT_LONGITUDE,
  );

  late MqttService _mqttService;
  StreamSubscription? _mqttSubscription;
  bool _isConnected = false;
  DateTime? _lastUpdateTime;
  bool _isFirstLocationUpdate = true;

  @override
  void initState() {
    super.initState();
    _initMqttService();
  }

  Future<void> _initMqttService() async {
    _mqttService = MqttService(
      id: 'flutter_map_client_${DateTime.now().millisecondsSinceEpoch}',
    );

    bool connected = await _mqttService.connect();
    if (mounted) {
      setState(() {
        _isConnected = connected;
      });
    }

    if (connected) {
      // Subscribe to GPS data
      _mqttService.subscribe(AppConfig.MQTT_GPS_TOPIC);

      // Listen for incoming messages
      _mqttSubscription = _mqttService.messageStream.listen(_handleMqttMessage);
    }
  }

  void _handleMqttMessage(Map<String, dynamic> event) {
    final topic = event['topic'];
    final message = event['message'];

    if (topic == AppConfig.MQTT_GPS_TOPIC) {
      try {
        // Message could be either Map (already decoded) or String (needs decoding)
        final Map<String, dynamic> gpsData =
            message is Map<String, dynamic>
                ? message
                : jsonDecode(message.toString());

        final double latitude = gpsData['latitude']?.toDouble() ?? 0.0;
        final double longitude = gpsData['longitude']?.toDouble() ?? 0.0;

        if (latitude != 0.0 && longitude != 0.0) {
          _updateVehicleLocation(latitude, longitude);
          _lastUpdateTime = DateTime.now();
        }
      } catch (e) {
        debugPrint('Error processing GPS message: $e');
      }
    }
  }

  void _updateVehicleLocation(double latitude, double longitude) {
    if (mounted) {
      setState(() {
        final LatLng position = LatLng(latitude, longitude);

        // Clear existing markers and add the new one
        _markers.clear();
        _markers.add(
          Marker(
            markerId: const MarkerId('vehicle'),
            position: position,
            infoWindow: InfoWindow(
              title: 'Vehicle',
              snippet: 'Lat: $latitude, Long: $longitude',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
          ),
        );

        // Automatically focus on the car's location when it's first received or updated
        if (_isFirstLocationUpdate) {
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: position, zoom: 16.0),
            ),
          );
          _isFirstLocationUpdate = false;
        } else {
          // For subsequent updates, just pan to the new position
          _mapController?.animateCamera(CameraUpdate.newLatLng(position));
        }
      });
    }
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _mqttService.disconnect();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Tracking')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _defaultLocation,
          zoom: AppConfig.DEFAULT_MAP_ZOOM,
        ),
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
        onMapCreated: (GoogleMapController controller) {
          _mapController = controller;
          _addDefaultMarker();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnVehicle,
        child: const Icon(Icons.directions_car),
      ),
    );
  }

  void _addDefaultMarker() {
    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('vehicle'),
          position: _defaultLocation,
          infoWindow: const InfoWindow(
            title: 'Vehicle',
            snippet: 'Waiting for GPS data...',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });
  }

  void _centerOnVehicle() {
    if (_markers.isNotEmpty) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _markers.first.position, zoom: 16.0),
        ),
      );
    } else {
      _mapController?.animateCamera(CameraUpdate.newLatLng(_defaultLocation));
    }
  }
}
