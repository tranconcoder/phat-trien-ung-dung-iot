import 'dart:async';
import 'dart:convert'; // Added for jsonDecode
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Added for Google Maps
import '../services/gps_mqtt_service.dart';
import '../services/mqtt_service.dart';
import '../config/app_config.dart';

class GpsMqttScreen extends StatefulWidget {
  const GpsMqttScreen({Key? key}) : super(key: key);

  @override
  State<GpsMqttScreen> createState() => _GpsMqttScreenState();
}

class _GpsMqttScreenState extends State<GpsMqttScreen> {
  final GpsMqttService _gpsMqttService = GpsMqttService(
      clientId: AppConfig.MQTT_CLIENT_ID_GPS); // Use ID from AppConfig
  final MqttService _mapMqttService = MqttService(
      id: 'flutter_map_client_${DateTime.now().millisecondsSinceEpoch}'); // Separate MQTT service for map
  bool _isInitialized = false;
  bool _isRunning = false;
  bool _isGpsServiceMqttConnected = false;
  bool _isMapMqttConnected = false;
  // Position? _lastPosition; // Can be removed if not directly used for display elsewhere
  StreamSubscription? _gpsServiceMqttStatusSubscription;
  StreamSubscription? _mapMqttStatusSubscription;
  StreamSubscription?
      _gpsDataSubscription; // For listening to GPS data for the map
  int _messagesSent = 0;
  String _status = 'Chưa khởi tạo';
  Timer? _statusTimer;

  // Google Map related state
  GoogleMapController? _mapController;
  LatLng _currentMapPosition =
      const LatLng(10.260451, 105.9431572); // Default initial position
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initializeServices();

    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRunning && mounted) {
        setState(() {
          // _messagesSent++; // This will be incremented when a message is actually sent by GpsMqttService
        });
      }
    });
  }

  @override
  void dispose() {
    _gpsMqttService.dispose();
    _mapMqttService.disconnect(); // Remove await since this returns void
    _gpsServiceMqttStatusSubscription?.cancel();
    _mapMqttStatusSubscription?.cancel();
    _gpsDataSubscription?.cancel();
    _statusTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize GPS sending service
      bool gpsServiceInitialized = await _gpsMqttService.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = gpsServiceInitialized;
          _isGpsServiceMqttConnected = _gpsMqttService.isMqttConnected;
          _status = gpsServiceInitialized
              ? 'Dịch vụ GPS sẵn sàng. '
              : 'Khởi tạo dịch vụ GPS thất bại. ';
        });
      }

      _gpsServiceMqttStatusSubscription =
          _gpsMqttService.mqttConnectionStatusStream.listen((connected) {
        if (mounted) {
          setState(() {
            _isGpsServiceMqttConnected = connected;
            if (!connected && _isInitialized) {
              _status += 'MQTT gửi GPS bị mất kết nối. ';
            } else if (connected && _isInitialized) {
              _status = _status.replaceAll('MQTT gửi GPS bị mất kết nối. ', '');
              _status += 'MQTT gửi GPS đã kết nối. ';
            }
          });
        }
      });

      // Initialize and connect MQTT service for map display
      await _initializeMapMqttService();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Lỗi khởi tạo: $e';
        });
      }
    }
  }

  Future<void> _initializeMapMqttService() async {
    try {
      bool mapMqttConnected = await _mapMqttService.connect();
      if (mounted) {
        setState(() {
          _isMapMqttConnected = mapMqttConnected;
          _status += mapMqttConnected
              ? 'MQTT bản đồ đã kết nối.'
              : 'MQTT bản đồ thất bại.';
        });
      }

      if (mapMqttConnected) {
        // MqttService now auto-subscribes to GPS_TOPIC on connection
        _listenToGpsMessages();
      }

      _mapMqttStatusSubscription =
          _mapMqttService.connectionStatusStream.listen((connected) {
        if (mounted) {
          setState(() {
            _isMapMqttConnected = connected;
            if (!connected) {
              _status = '${_status.replaceAll('MQTT bản đồ đã kết nối.', '')}MQTT bản đồ bị mất kết nối.';
              // Attempt to reconnect map MQTT service
              _mapMqttService.connect();
            } else {
              _status = '${_status.replaceAll('MQTT bản đồ bị mất kết nối.', '')}MQTT bản đồ đã kết nối.';
              _listenToGpsMessages(); // Re-listen if not already
            }
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status += ' Lỗi MQTT bản đồ: $e';
        });
      }
    }
  }

  void _listenToGpsMessages() {
    _gpsDataSubscription?.cancel(); // Cancel previous subscription if any
    _gpsDataSubscription = _mapMqttService.messageStream.listen((event) {
      final topic = event['topic'];
      final message = event['message'];

      if (topic == AppConfig.MQTT_GPS_TOPIC) {
        try {
          // Message is already decoded to Map<String, dynamic> by MqttService if it's JSON
          final Map<String, dynamic> gpsData = message is Map<String, dynamic>
              ? message
              : jsonDecode(message.toString());

          final double latitude = gpsData['latitude']?.toDouble();
          final double longitude = gpsData['longitude']?.toDouble();
          // final int timestamp = gpsData['timestamp']?.toInt();
          // final double speed = gpsData['speed']?.toDouble();
          // final double heading = gpsData['heading']?.toDouble();

          if (mounted) {
            setState(() {
              _currentMapPosition = LatLng(latitude, longitude);
              _markers.clear();
              _markers.add(
                Marker(
                  markerId: const MarkerId('currentLocation'),
                  position: _currentMapPosition,
                  infoWindow: InfoWindow(
                      title: 'Vị trí hiện tại',
                      snippet: '$latitude, $longitude'),
                ),
              );
            });
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(_currentMapPosition),
            );
          }
        } catch (e) {
          debugPrint('Error processing GPS message: $e');
          if (mounted) {
            // Optionally update status
            // _status = 'Lỗi xử lý dữ liệu GPS: $e';
          }
        }
      }
    });
  }

  Future<void> _reconnectMqtt() async {
    setState(() {
      _status = 'Đang kết nối lại MQTT...';
    });
    // Reconnect GPS sending service
    if (_isInitialized) {
      await _gpsMqttService.stop(); // Stop before re-initializing
    }
    bool gpsServiceReconnected = await _gpsMqttService.initialize();

    // Reconnect Map MQTT service
    _mapMqttService.disconnect(); // Remove await since this returns void
    bool mapServiceReconnected = await _mapMqttService.connect();

    if (mounted) {
      setState(() {
        _isInitialized = gpsServiceReconnected;
        _isGpsServiceMqttConnected = _gpsMqttService.isMqttConnected;
        _isMapMqttConnected = mapServiceReconnected;
        _status = (gpsServiceReconnected
                ? 'Dịch vụ GPS đã kết nối lại. '
                : 'Dịch vụ GPS kết nối lại thất bại. ') +
            (mapServiceReconnected
                ? 'MQTT bản đồ đã kết nối lại.'
                : 'MQTT bản đồ kết nối lại thất bại.');
        if (mapServiceReconnected) {
          _listenToGpsMessages();
        }
      });
    }
  }

  Future<void> _toggleService() async {
    if (_isRunning) {
      await _gpsMqttService.stop();
      if (mounted) {
        setState(() {
          _isRunning = false;
          _status = 'Đã dừng gửi dữ liệu GPS.';
        });
      }
    } else {
      if (!_isInitialized) {
        await _initializeServices(); // Ensure services are initialized first
        if (!_isInitialized) {
          setState(() {
            _status = 'Không thể khởi tạo dịch vụ. Vui lòng thử lại.';
          });
          return;
        }
      }
      try {
        // Listen for actual sent messages to update the counter
        // This requires GpsMqttService to expose a stream of sent messages or a callback
        // For simplicity, we'll rely on the timer for now, or GpsMqttService can update a counter.
        // Let's assume GpsMqttService handles its own message count if needed.
        // For this screen, _messagesSent will just be an indicator of active sending time.

        bool started =
            await _gpsMqttService.startSendingGpsData(onMessageSent: () {
          if (mounted) {
            setState(() {
              _messagesSent++;
            });
          }
        });
        if (mounted) {
          setState(() {
            _isRunning = started;
            if (started) {
              _messagesSent = 0; // Reset counter on start
              _status = 'Đang gửi dữ liệu GPS...';
            } else {
              _status =
                  'Không thể bắt đầu gửi dữ liệu GPS. Kiểm tra kết nối MQTT của dịch vụ GPS.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _status = 'Lỗi khi bắt đầu dịch vụ: $e';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS qua MQTT & Bản đồ'), // Updated title
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Kết nối lại MQTT',
            onPressed: _reconnectMqtt,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Trạng thái dịch vụ GPS-MQTT',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Status card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusItem(
                        title: 'Khởi tạo dịch vụ GPS:',
                        value: _isInitialized ? 'Đã khởi tạo' : 'Chưa khởi tạo',
                        isActive: _isInitialized,
                      ),
                      StatusItem(
                        title: 'MQTT gửi GPS:',
                        value: _isGpsServiceMqttConnected
                            ? 'Đã kết nối'
                            : 'Chưa kết nối',
                        isActive: _isGpsServiceMqttConnected,
                      ),
                      StatusItem(
                        title: 'MQTT bản đồ:',
                        value:
                            _isMapMqttConnected ? 'Đã kết nối' : 'Chưa kết nối',
                        isActive: _isMapMqttConnected,
                      ),
                      StatusItem(
                        title: 'Trạng thái gửi GPS:',
                        value: _isRunning ? 'Đang chạy' : 'Đã dừng',
                        isActive: _isRunning,
                      ),
                      const StatusItem(
                        title: 'Địa chỉ máy chủ MQTT:',
                        value: AppConfig.MQTT_HOST,
                        isActive: true,
                      ),
                      const StatusItem(
                        title: 'Topic GPS:',
                        value: AppConfig.MQTT_GPS_TOPIC,
                        isActive: true,
                      ),
                      const StatusItem(
                        title: 'Tần suất gửi:',
                        value: '${AppConfig.LOCATION_UPDATE_INTERVAL}ms',
                        isActive: true,
                      ),
                      StatusItem(
                        title: 'Số tin nhắn đã gửi:',
                        value: _isRunning ? '$_messagesSent' : 'N/A', // Updated
                        isActive: _isRunning,
                      ),
                      const Divider(),
                      Text(
                        'Trạng thái: $_status',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),

                      // Reconnect button
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Center(
                          child: ElevatedButton.icon(
                            onPressed: _reconnectMqtt,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Kết nối lại MQTT'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Map View
              SizedBox(
                height: 300,
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentMapPosition,
                        zoom: 16.0,
                      ),
                      onMapCreated: (GoogleMapController controller) {
                        _mapController = controller;
                      },
                      markers: _markers,
                      myLocationEnabled:
                          false, // Set to true if you want to show device's blue dot
                      myLocationButtonEnabled: false,
                      mapType: MapType.normal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Control buttons (Keep this section)
              Center(
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isInitialized ? _toggleService : _initializeServices,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        backgroundColor:
                            _isRunning ? Colors.redAccent : Colors.green,
                      ),
                      child: Text(
                        _isInitialized
                            ? (_isRunning ? 'Dừng gửi GPS' : 'Bắt đầu gửi GPS')
                            : 'Khởi tạo dịch vụ',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_isInitialized)
                      const Text(
                        'Bạn cần khởi tạo dịch vụ trước khi sử dụng.',
                        style: TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),

              // const Spacer(), // Remove Spacer
              const SizedBox(height: 16), // Add some space before footer

              // Footer (Keep this section)
              const Center(
                child: Text(
                  'Dữ liệu GPS sẽ được gửi tới MQTT broker mỗi giây',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16), // Add padding at the bottom
            ],
          ),
        ),
      ),
    );
  }
}

class StatusItem extends StatelessWidget {
  final String title;
  final String value;
  final bool isActive;

  const StatusItem({
    Key? key,
    required this.title,
    required this.value,
    this.isActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(value),
            ],
          ),
        ],
      ),
    );
  }
}
