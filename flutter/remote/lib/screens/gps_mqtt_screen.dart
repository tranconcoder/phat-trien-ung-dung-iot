import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gps_mqtt_service.dart';
import '../services/mqtt_service.dart';
import '../config/app_config.dart';

class GpsMqttScreen extends StatefulWidget {
  const GpsMqttScreen({Key? key}) : super(key: key);

  @override
  State<GpsMqttScreen> createState() => _GpsMqttScreenState();
}

class _GpsMqttScreenState extends State<GpsMqttScreen> {
  final GpsMqttService _gpsMqttService =
      GpsMqttService(clientId: 'flutter_gps_client');
  final MqttService _mqttService = MqttService();
  bool _isInitialized = false;
  bool _isRunning = false;
  bool _isMqttConnected = false;
  Position? _lastPosition;
  StreamSubscription? _mqttStatusSubscription;
  int _messagesSent = 0;
  String _status = 'Chưa khởi tạo';
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _initializeService();

    // Update UI status periodically
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRunning && mounted) {
        setState(() {
          _messagesSent++;
        });
      }
    });
  }

  @override
  void dispose() {
    _gpsMqttService.dispose();
    _mqttStatusSubscription?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeService() async {
    try {
      bool initialized = await _gpsMqttService.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = initialized;
          _isMqttConnected = _gpsMqttService.isMqttConnected;
          _status = initialized
              ? 'Đã khởi tạo. Sẵn sàng để gửi dữ liệu GPS.'
              : 'Khởi tạo thất bại. Vui lòng kiểm tra quyền và kết nối.';
        });
      }

      // Listen to MQTT connection status changes
      _mqttStatusSubscription =
          _gpsMqttService.mqttConnectionStatusStream.listen((connected) {
        if (mounted) {
          setState(() {
            _isMqttConnected = connected;
            if (!connected) {
              _status = 'Mất kết nối MQTT. Đang thử kết nối lại...';
            } else {
              _status = 'Đã kết nối MQTT.';
            }
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Lỗi: $e';
        });
      }
    }
  }

  Future<void> _reconnectMqtt() async {
    try {
      setState(() {
        _status = 'Đang kết nối lại MQTT...';
      });

      // Stop any existing service first
      if (_isRunning) {
        await _gpsMqttService.stop();
        setState(() {
          _isRunning = false;
        });
      }

      // Reinitialize
      bool initialized = await _gpsMqttService.initialize();

      setState(() {
        _isInitialized = initialized;
        _isMqttConnected = _gpsMqttService.isMqttConnected;
        _status = initialized
            ? 'Đã kết nối lại MQTT thành công'
            : 'Kết nối lại MQTT thất bại';
      });
    } catch (e) {
      setState(() {
        _status = 'Lỗi khi kết nối lại: $e';
      });
    }
  }

  Future<void> _toggleService() async {
    if (_isRunning) {
      // Stop service
      await _gpsMqttService.stop();
      if (mounted) {
        setState(() {
          _isRunning = false;
          _status = 'Đã dừng gửi dữ liệu GPS.';
        });
      }
    } else {
      // Start service
      try {
        bool started = await _gpsMqttService.startSendingGpsData();
        if (mounted) {
          setState(() {
            _isRunning = started;
            _messagesSent = 0;
            _status = started
                ? 'Đang gửi dữ liệu GPS...'
                : 'Không thể bắt đầu gửi dữ liệu GPS.';
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
        title: const Text('Gửi GPS qua MQTT'),
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
                      title: 'Trạng thái khởi tạo:',
                      value: _isInitialized ? 'Đã khởi tạo' : 'Chưa khởi tạo',
                      isActive: _isInitialized,
                    ),
                    StatusItem(
                      title: 'Kết nối MQTT:',
                      value: _isMqttConnected ? 'Đã kết nối' : 'Chưa kết nối',
                      isActive: _isMqttConnected,
                    ),
                    StatusItem(
                      title: 'Trạng thái dịch vụ:',
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
                      value: _isRunning ? '$_messagesSent' : '0',
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

            // Control buttons
            Center(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed:
                        _isInitialized ? _toggleService : _initializeService,
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
                      style: const TextStyle(fontSize: 16, color: Colors.white),
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

            const Spacer(),

            // Footer
            const Center(
              child: Text(
                'Dữ liệu GPS sẽ được gửi tới MQTT broker mỗi giây',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
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
