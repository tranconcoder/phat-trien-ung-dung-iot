import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import '../services/mqtt_service.dart';
import '../config/app_config.dart';

class VehicleMetricsScreen extends StatefulWidget {
  const VehicleMetricsScreen({Key? key}) : super(key: key);

  @override
  State<VehicleMetricsScreen> createState() => _VehicleMetricsScreenState();
}

class _VehicleMetricsScreenState extends State<VehicleMetricsScreen> {
  // MQTT Service
  final MqttService _mqttService = MqttService(id: 'metrics_control');
  bool _mqttConnected = false;
  String _mqttStatus = "Chưa kết nối";

  // Text editing controllers for manual input
  final TextEditingController _speedController = TextEditingController();
  final TextEditingController _batteryLevelController = TextEditingController();
  final TextEditingController _temperatureController = TextEditingController();
  final TextEditingController _energyConsumptionController =
      TextEditingController();
  final TextEditingController _rangeController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();
  final TextEditingController _engineTempController = TextEditingController();
  final TextEditingController _controllerTempController =
      TextEditingController();
  final TextEditingController _batteryTempController = TextEditingController();

  // Simulated metrics
  double _speed = 0.0;
  double _batteryLevel = 85.0;
  double _temperature = 27.5;
  double _energyConsumption = 13.2; // kWh/100km
  double _range = 320; // km
  final String _status = "Hoạt động bình thường";
  Timer? _simulationTimer;

  // Automatic sending
  bool _autoSendMetrics = false;
  Timer? _autoSendTimer;

  // Manual input mode
  bool _manualInputMode = false;

  // History data for charts
  final List<double> _speedHistory = [];
  final List<double> _batteryHistory = [];
  final List<double> _temperatureHistory = [];

  @override
  void initState() {
    super.initState();
    _startSimulation();
    _initializeMqtt();
    _initializeTextControllers();
  }

  void _initializeTextControllers() {
    _speedController.text = _speed.toString();
    _batteryLevelController.text = _batteryLevel.toString();
    _temperatureController.text = _temperature.toString();
    _energyConsumptionController.text = _energyConsumption.toString();
    _rangeController.text = _range.toString();
    _statusController.text = _status;
    _engineTempController.text = (_temperature + 8.5).toString();
    _controllerTempController.text = _temperature.toString();
    _batteryTempController.text = (_temperature + 3.2).toString();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _autoSendTimer?.cancel();
    _mqttService.disconnect();

    // Dispose text controllers
    _speedController.dispose();
    _batteryLevelController.dispose();
    _temperatureController.dispose();
    _energyConsumptionController.dispose();
    _rangeController.dispose();
    _statusController.dispose();
    _engineTempController.dispose();
    _controllerTempController.dispose();
    _batteryTempController.dispose();

    super.dispose();
  }

  Future<void> _initializeMqtt() async {
    try {
      bool connected = await _mqttService.connect();
      setState(() {
        _mqttConnected = connected;
        _mqttStatus = connected ? "Đã kết nối" : "Kết nối thất bại";
      });

      // Listen to connection status updates
      _mqttService.connectionStatusStream.listen((connected) {
        if (mounted) {
          setState(() {
            _mqttConnected = connected;
            _mqttStatus = connected ? "Đã kết nối" : "Mất kết nối";
          });
        }
      });
    } catch (e) {
      setState(() {
        _mqttConnected = false;
        _mqttStatus = "Lỗi: $e";
      });
    }
  }

  void _reconnectMqtt() async {
    setState(() {
      _mqttStatus = "Đang kết nối...";
    });

    try {
      bool connected = await _mqttService.connect();
      setState(() {
        _mqttConnected = connected;
        _mqttStatus = connected ? "Đã kết nối" : "Kết nối thất bại";
      });
    } catch (e) {
      setState(() {
        _mqttConnected = false;
        _mqttStatus = "Lỗi: $e";
      });
    }
  }

  void _sendMetrics() {
    if (!_mqttConnected) {
      _showSnackBar("Chưa kết nối MQTT");
      return;
    }

    final Map<String, dynamic> metrics = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'vehicle_id': 'vehicle1',
    };

    // Get values from text controllers if in manual mode, otherwise use simulated values
    double speed = _manualInputMode
        ? double.tryParse(_speedController.text) ?? _speed
        : _speed;
    double battery = _manualInputMode
        ? double.tryParse(_batteryLevelController.text) ?? _batteryLevel
        : _batteryLevel;
    double range = _manualInputMode
        ? double.tryParse(_rangeController.text) ?? _range
        : _range;
    double consumption = _manualInputMode
        ? double.tryParse(_energyConsumptionController.text) ??
            _energyConsumption
        : _energyConsumption;
    double engineTemp = _manualInputMode
        ? double.tryParse(_engineTempController.text) ?? (_temperature + 8.5)
        : (_temperature + 8.5);
    double controllerTemp = _manualInputMode
        ? double.tryParse(_controllerTempController.text) ?? _temperature
        : _temperature;
    double batteryTemp = _manualInputMode
        ? double.tryParse(_batteryTempController.text) ?? (_temperature + 3.2)
        : (_temperature + 3.2);

    metrics['speed'] = speed;
    metrics['battery'] = battery;
    metrics['range'] = range;
    metrics['consumption'] = consumption;
    metrics['engine_temp'] = engineTemp;
    metrics['controller_temp'] = controllerTemp;
    metrics['battery_temp'] = batteryTemp;
    _mqttService.publishMessage(
        AppConfig.MQTT_METRICS_TOPIC, jsonEncode(metrics));
    _showSnackBar("Đã gửi tất cả dữ liệu");
  }

  void _toggleAutoSend() {
    setState(() {
      _autoSendMetrics = !_autoSendMetrics;
    });

    if (_autoSendMetrics) {
      // Send metrics every 5 seconds
      _autoSendTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _sendMetrics();
      });
      _showSnackBar("Bật tự động gửi dữ liệu (5 giây/lần)");
    } else {
      _autoSendTimer?.cancel();
      _autoSendTimer = null;
      _showSnackBar("Tắt tự động gửi dữ liệu");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startSimulation() {
    // Initialize history with current values
    for (int i = 0; i < 20; i++) {
      _speedHistory.add(_speed);
      _batteryHistory.add(_batteryLevel);
      _temperatureHistory.add(_temperature);
    }

    // Update metrics every second
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        // Generate slightly random variations for simulation
        final random = math.Random();

        // Update speed (0-120 km/h)
        _speed += (random.nextDouble() * 10) - 4; // -4 to +6
        _speed = _speed.clamp(0, 120);
        _speedHistory.add(_speed);
        if (_speedHistory.length > 60) _speedHistory.removeAt(0);

        // Gradually decrease battery
        _batteryLevel -= random.nextDouble() * 0.2;
        _batteryLevel = _batteryLevel.clamp(0, 100);
        _batteryHistory.add(_batteryLevel);
        if (_batteryHistory.length > 60) _batteryHistory.removeAt(0);

        // Update temperature
        _temperature += (random.nextDouble() - 0.5) * 0.3;
        _temperature = _temperature.clamp(20, 40);
        _temperatureHistory.add(_temperature);
        if (_temperatureHistory.length > 60) _temperatureHistory.removeAt(0);

        // Update consumption based on speed
        _energyConsumption = 10 + (_speed / 20);

        // Update range based on battery and consumption
        _range =
            (_batteryLevel / 100) * (100 / (_energyConsumption / 100)) * 100;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông số xe'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: _manualInputMode ? 'Chế độ tự động' : 'Nhập thủ công',
            onPressed: () => setState(() {
              _manualInputMode = !_manualInputMode;
              if (!_manualInputMode) {
                _initializeTextControllers();
              }
              if (_manualInputMode) {
                _simulationTimer?.cancel();
              } else {
                _startSimulation();
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Kết nối lại MQTT',
            onPressed: _reconnectMqtt,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Simulate fetching new data
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // MQTT Status Card
              _buildMqttStatusCard(),

              const SizedBox(height: 16),

              // Primary metrics cards
              _buildPrimaryMetrics(),

              const SizedBox(height: 16),

              // Battery details
              _buildBatteryCard(),

              const SizedBox(height: 16),

              // Temperature details
              _buildTemperatureCard(),

              const SizedBox(height: 16),

              // Speed and driving behavior
              _buildSpeedCard(),

              const SizedBox(height: 16),

              // Status and notifications
              _buildStatusCard(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _sendMetrics(),
        icon: const Icon(Icons.send),
        label: const Text('Gửi tất cả'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildMqttStatusCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _mqttConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _mqttConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                const Text(
                  "MQTT Status",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _autoSendMetrics,
                  onChanged: _manualInputMode ? null : (_) => _toggleAutoSend(),
                  activeColor: Colors.green,
                ),
                Text(
                  _autoSendMetrics ? "Tự động" : "Thủ công",
                  style: TextStyle(
                    color: _autoSendMetrics ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Trạng thái: $_mqttStatus"),
            const Text("Topic: ${AppConfig.MQTT_METRICS_TOPIC}"),
            const SizedBox(height: 12),
            if (_manualInputMode) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                "Nhập thủ công",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildManualInputForm(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: _mqttConnected ? onPressed : null,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildPrimaryMetrics() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: "Tốc độ",
            value: "${_speed.round()}",
            unit: "km/h",
            icon: Icons.speed,
            color: _getSpeedColor(_speed),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: "Pin",
            value: "${_batteryLevel.round()}",
            unit: "%",
            icon: Icons.battery_charging_full,
            color: _getBatteryColor(_batteryLevel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: "Nhiệt độ",
            value: _temperature.toStringAsFixed(1),
            unit: "°C",
            icon: Icons.thermostat,
            color: _getTemperatureColor(_temperature),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.battery_charging_full,
                  color: _getBatteryColor(_batteryLevel),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Chi tiết pin",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Battery level bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _batteryLevel / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getBatteryColor(_batteryLevel),
                ),
                minHeight: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Mức pin: ${_batteryLevel.round()}%",
              style: const TextStyle(fontSize: 16),
            ),

            const Divider(height: 24),

            // Additional battery info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem("Phạm vi", "${_range.round()} km"),
                _buildInfoItem("Tiêu thụ",
                    "${_energyConsumption.toStringAsFixed(1)} kWh/100km"),
                _buildInfoItem("Thời gian sạc đầy", "1.5 giờ"),
              ],
            ),

            const SizedBox(height: 16),

            // Battery history
            SizedBox(
              height: 100,
              child: _buildHistoryChart(
                  _batteryHistory, _getBatteryColor(_batteryLevel)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemperatureCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.thermostat,
                  color: _getTemperatureColor(_temperature),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Nhiệt độ hệ thống",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Temperature components
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTemperatureComponent(
                  name: "Động cơ",
                  temp: _temperature + 8.5,
                ),
                _buildTemperatureComponent(
                  name: "Bộ điều khiển",
                  temp: _temperature,
                ),
                _buildTemperatureComponent(
                  name: "Pin",
                  temp: _temperature + 3.2,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Temperature history chart
            SizedBox(
              height: 100,
              child: _buildHistoryChart(
                  _temperatureHistory, _getTemperatureColor(_temperature)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemperatureComponent(
      {required String name, required double temp}) {
    final color = _getTemperatureColor(temp);
    return Column(
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              "${temp.toStringAsFixed(1)}°C",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.speed,
                  color: _getSpeedColor(_speed),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Tốc độ & Hiệu suất",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Speedometer visualization
            Center(
              child: SizedBox(
                height: 160,
                width: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Speedometer background
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                      ),
                    ),

                    // Speed indicator
                    Transform.rotate(
                      angle: (_speed / 120) * 1.5 * math.pi,
                      child: Container(
                        height: 80,
                        width: 4,
                        decoration: BoxDecoration(
                          color: _getSpeedColor(_speed),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        alignment: Alignment.topCenter,
                      ),
                    ),

                    // Center circle
                    Container(
                      height: 20,
                      width: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getSpeedColor(_speed),
                      ),
                    ),

                    // Speed text
                    Positioned(
                      bottom: 40,
                      child: Column(
                        children: [
                          Text(
                            _speed.round().toString(),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: _getSpeedColor(_speed),
                            ),
                          ),
                          const Text(
                            "km/h",
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Speed history chart
            SizedBox(
              height: 100,
              child: _buildHistoryChart(_speedHistory, _getSpeedColor(_speed)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue[700],
                ),
                const SizedBox(width: 8),
                const Text(
                  "Trạng thái",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Trạng thái hệ thống",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_status),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Last check and next maintenance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem("Kiểm tra cuối", "Hôm nay"),
                _buildInfoItem("Bảo dưỡng tiếp theo", "15 ngày"),
                _buildInfoItem("Phiên bản phần mềm", "2.3.4"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryChart(List<double> data, Color color) {
    if (data.isEmpty) return const SizedBox();

    final max = data.reduce(math.max);
    final min = data.reduce(math.min);
    final range = max - min > 0 ? max - min : 1.0;

    return CustomPaint(
      painter: _ChartPainter(
        data: data,
        color: color,
        min: min,
        range: range,
      ),
    );
  }

  Widget _buildManualInputForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Speed input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _speedController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tốc độ (km/h)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Battery inputs
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _batteryLevelController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pin (%)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _rangeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Phạm vi (km)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Energy consumption
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _energyConsumptionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiêu thụ (kWh/100km)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _statusController,
                decoration: const InputDecoration(
                  labelText: 'Trạng thái',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Temperature inputs
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _engineTempController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nhiệt độ động cơ (°C)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controllerTempController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nhiệt độ bộ điều khiển (°C)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Battery temperature
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _batteryTempController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nhiệt độ pin (°C)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container()),
          ],
        ),

        const SizedBox(height: 16),

        // Send button
        Center(
          child: ElevatedButton.icon(
            onPressed: _mqttConnected ? () => _sendMetrics() : null,
            icon: const Icon(Icons.send),
            label: const Text('Gửi tất cả thông số'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Color _getSpeedColor(double speed) {
    if (speed < 40) return Colors.green;
    if (speed < 80) return Colors.orange;
    return Colors.red;
  }

  Color _getBatteryColor(double level) {
    if (level < 20) return Colors.red;
    if (level < 50) return Colors.orange;
    return Colors.green;
  }

  Color _getTemperatureColor(double temp) {
    if (temp < 25) return Colors.blue;
    if (temp < 32) return Colors.green;
    if (temp < 38) return Colors.orange;
    return Colors.red;
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double min;
  final double range;

  _ChartPainter({
    required this.data,
    required this.color,
    required this.min,
    required this.range,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final width = size.width;
    final height = size.height;
    final stepX = width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = (data[i] - min) / range;
      final y = height - (normalizedValue * height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(width, height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
