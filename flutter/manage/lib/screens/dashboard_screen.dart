import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:quan_ly_giao_thong/models/vehicle_metrics.dart';
import 'package:quan_ly_giao_thong/config/app_config.dart';

// MQTT connection states
enum MqttConnectionState { disconnected, connecting, connected, error }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // MQTT client
  MqttServerClient? _client;

  // MQTT connection parameters
  String _brokerAddress = AppConfig.MQTT_HOST;
  int _port = AppConfig.MQTT_PORT;

  // Stream controllers
  final _metricsController = StreamController<VehicleMetrics>.broadcast();
  final _connectionStateController =
      StreamController<MqttConnectionState>.broadcast();

  // Flag to prevent using closed streams
  bool _isDisposed = false;

  // Subscriptions
  late StreamSubscription<VehicleMetrics> _metricsSubscription;
  late StreamSubscription<MqttConnectionState> _connectionSubscription;

  // Metrics and connection state
  late VehicleMetrics _metrics;
  MqttConnectionState _connectionState = MqttConnectionState.disconnected;

  // Message tracking
  DateTime? _lastMessageTime;
  int _messageCount = 0;
  String _lastTopic = "";

  // Debug mode
  bool _debugMode = false;

  @override
  void initState() {
    super.initState();

    // Initialize default metrics
    _metrics = VehicleMetrics(
      speed: 0,
      energy: 80,
      energyConsumption: 5.5,
      location: LatLng(AppConfig.DEFAULT_LATITUDE, AppConfig.DEFAULT_LONGITUDE),
      temperature: 0,
      humidity: 0,
    );

    // Connect to MQTT broker
    _setupMqttConnection();

    // Listen for metrics updates
    _metricsSubscription = _metricsController.stream.listen((metrics) {
      if (mounted) {
        setState(() {
          _metrics = metrics;
        });
      }
    });

    // Listen for connection state changes
    _connectionSubscription = _connectionStateController.stream.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
        });
      }
    });
  }

  // Set up MQTT connection
  void _setupMqttConnection() {
    if (!mounted || _isDisposed) return;

    _connectionState = MqttConnectionState.connecting;
    try {
      _connectionStateController.add(_connectionState);
    } catch (e) {
      print('Error updating connection state: $e');
      return;
    }

    // Use broker from AppConfig
    _brokerAddress = AppConfig.MQTT_HOST;
    _port = AppConfig.MQTT_PORT;
    final String clientId =
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}';

    print(
      'Connecting to MQTT broker: $_brokerAddress:$_port with clientId: $clientId',
    );

    _client = MqttServerClient.withPort(_brokerAddress, clientId, _port);

    // Configure client
    _client!.keepAlivePeriod = AppConfig.MQTT_KEEP_ALIVE;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    // Set longer connection timeout
    _client!.connectTimeoutPeriod = 30000; // 30 seconds

    // Configure TLS if enabled in AppConfig
    if (AppConfig.MQTT_USE_TLS) {
      print('Configuring secure connection with TLS');
      _client!.secure = true;

      try {
        final context = SecurityContext.defaultContext;
        _client!.securityContext = context;

        // Add certificate verification bypass for development
        _client!.onBadCertificate = (dynamic certificate) {
          print('Accepting bad certificate');
          return true; // Accept all certificates for now
        };
      } catch (e) {
        print('Error setting up security context: $e');
        // Continue with insecure connection as fallback
        print('Falling back to insecure connection');
        _client!.secure = false;
      }
    }

    // Configure client logging
    _client!.logging(on: true);

    // Set up the connection message with clean session and keep alive
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean() // Essential for clean session
        .keepAliveFor(30) // Seconds to keep connection alive
        .withWillQos(MqttQos.atLeastOnce);

    // Add authentication if provided
    if (AppConfig.MQTT_USERNAME.isNotEmpty) {
      print('Using authentication with username: ${AppConfig.MQTT_USERNAME}');
      connMessage.authenticateAs(
        AppConfig.MQTT_USERNAME,
        AppConfig.MQTT_PASSWORD,
      );
    }

    _client!.connectionMessage = connMessage;

    // Start with DNS check before connection
    _checkHostResolution();
  }

  // Attempt direct connection to broker (bypassing DNS)
  void _tryDirectConnection() {
    // Skip if not mounted or disposed
    if (!mounted || _isDisposed) return;

    print(
      'Attempting direct IP connection to ${AppConfig.MQTT_FALLBACK_HOST}:${AppConfig.MQTT_FALLBACK_PORT}',
    );

    // Update connection state
    _connectionState = MqttConnectionState.connecting;
    try {
      _connectionStateController.add(_connectionState);
    } catch (e) {
      print('Error updating connection state: $e');
    }

    // Create new client with direct IP address
    final String clientId =
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    _brokerAddress =
        AppConfig.MQTT_FALLBACK_HOST; // Use the IP address directly
    _port = AppConfig.MQTT_FALLBACK_PORT; // Non-TLS port

    _client = MqttServerClient.withPort(_brokerAddress, clientId, _port);

    // Configure client
    _client!.keepAlivePeriod = AppConfig.MQTT_KEEP_ALIVE;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.connectTimeoutPeriod =
        10000; // Shorter timeout for direct connection
    _client!.secure = false; // No TLS for direct IP connection

    // Set up message
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .keepAliveFor(30)
        .withWillQos(MqttQos.atLeastOnce);

    // Add authentication
    if (AppConfig.MQTT_USERNAME.isNotEmpty) {
      connMessage.authenticateAs(
        AppConfig.MQTT_USERNAME,
        AppConfig.MQTT_PASSWORD,
      );
    }

    _client!.connectionMessage = connMessage;

    // Connect directly
    _connectToBroker(isDirectConnection: true);
  }

  // Connect to broker with error handling
  void _connectToBroker({bool isDirectConnection = false}) {
    print('MQTT Connecting to $_brokerAddress:$_port');
    print('Using TLS: ${_client!.secure}');
    print('Using auth: ${AppConfig.MQTT_USERNAME.isNotEmpty}');
    print('Using client ID: ${_client!.clientIdentifier}');

    try {
      _client!
          .connect()
          .then((_) {
            // Check for successful connection
            final returnCode = _client!.connectionStatus!.returnCode;
            print('MQTT connection return code: $returnCode');

            if (returnCode == MqttConnectReturnCode.connectionAccepted) {
              print('MQTT Connected successfully');
              print('Connection status: ${_client!.connectionStatus}');
              _connectionState = MqttConnectionState.connected;
              try {
                _connectionStateController.add(_connectionState);
              } catch (e) {
                print('Error updating connection state: $e');
              }
              _subscribeToTopics();

              // Show success message to user
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Connected to MQTT broker: $_brokerAddress'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              print(
                'MQTT Connection failed - Client status: ${_client!.connectionStatus}',
              );
              print('Return code: $returnCode');

              // If not direct connection, try direct connection first
              if (!isDirectConnection) {
                _tryDirectConnection();
              } else {
                _handleConnectionFailure();
              }
            }
          })
          .catchError((error) {
            print('MQTT Connection error: $error');
            print('Error type: ${error.runtimeType}');
            print('Connection status: ${_client?.connectionStatus}');

            // If not direct connection, try direct connection first
            if (!isDirectConnection) {
              _tryDirectConnection();
            } else {
              _handleConnectionFailure();
            }
          });
    } catch (e) {
      print('Exception during MQTT connection: $e');
      print('Exception type: ${e.runtimeType}');

      // If not direct connection, try direct connection first
      if (!isDirectConnection) {
        _tryDirectConnection();
      } else {
        _handleConnectionFailure();
      }
    }
  }

  // Handle connection failure and try fallback options
  void _handleConnectionFailure() {
    // Safely update state if component is still mounted
    if (!mounted || _isDisposed) return;

    _connectionState = MqttConnectionState.error;
    try {
      _connectionStateController.add(_connectionState);
    } catch (e) {
      print('Error updating connection state: $e');
      // Cannot update state, might be disposed
      return;
    }

    // Try public broker as last resort
    print(
      'All connection attempts failed. Trying public broker as last resort...',
    );
    _brokerAddress = AppConfig.MQTT_PUBLIC_HOST;
    _port = AppConfig.MQTT_PUBLIC_PORT;

    // Create new client with public broker
    final String clientId =
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(_brokerAddress, clientId, _port);

    // Basic configuration
    _client!.keepAlivePeriod = AppConfig.MQTT_KEEP_ALIVE;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.connectTimeoutPeriod = 10000; // Shorter timeout
    _client!.secure = false; // Public broker without TLS

    // Public broker usually doesn't need auth
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    // Show notification to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trying public MQTT broker as fallback'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    // Try public broker connection
    _connectToBroker(isDirectConnection: true);
  }

  // Helper method for reconnection scheduling
  void _scheduleReconnect() {
    // Try to reconnect after a delay if widget is still mounted
    if (!mounted || _isDisposed) return;

    // Check if we're already connected (avoid duplicate connection attempts)
    if (_connectionState == MqttConnectionState.connected) return;

    print('Scheduling reconnect in ${AppConfig.MQTT_RECONNECT_DELAY} seconds');
    Future.delayed(Duration(seconds: AppConfig.MQTT_RECONNECT_DELAY), () {
      if (!mounted || _isDisposed) return;
      if (_connectionState != MqttConnectionState.connected) {
        // Try to resolve DNS before attempting connection
        _checkHostResolution();
      }
    });
  }

  // Check DNS resolution before connecting
  void _checkHostResolution() {
    print('Testing DNS resolution for $_brokerAddress');

    try {
      InternetAddress.lookup(_brokerAddress)
          .then((addresses) {
            if (addresses.isNotEmpty) {
              // Log IP addresses for debugging
              final ips = addresses.map((addr) => addr.address).join(', ');
              print('DNS resolution successful. IP address(es): $ips');

              // Use the first IP address directly if available
              // This bypasses DNS for subsequent connection attempts
              if (addresses.first.type == InternetAddressType.IPv4) {
                final ipAddress = addresses.first.address;
                print('Using direct IP address: $ipAddress');
                _brokerAddress = ipAddress;
              }

              _connectToBroker();
            } else {
              print('DNS resolution failed - no addresses returned');

              // Skip to direct connection as fallback
              _tryDirectConnection();
            }
          })
          .catchError((error) {
            print('Error during DNS lookup: $error');

            // Skip to direct connection on DNS error
            _tryDirectConnection();
          });
    } catch (e) {
      print('Exception during DNS resolution: $e');
      // Skip to direct connection
      _tryDirectConnection();
    }
  }

  // Subscribe to topics
  void _subscribeToTopics() {
    try {
      print('Attempting to subscribe to topics...');

      // Subscribe to metrics topic from AppConfig
      print('Subscribing to topic: ${AppConfig.MQTT_METRICS_TOPIC}');
      _client?.subscribe(AppConfig.MQTT_METRICS_TOPIC, MqttQos.atLeastOnce);

      // Also subscribe to regular topic format without leading slash
      // as some brokers handle this differently
      if (AppConfig.MQTT_METRICS_TOPIC.startsWith('/')) {
        final String altTopic = AppConfig.MQTT_METRICS_TOPIC.substring(1);
        print('Also subscribing to alternative topic format: $altTopic');
        _client?.subscribe(altTopic, MqttQos.atLeastOnce);
      }

      print('Successfully subscribed to topics');

      // Reset message counts
      _lastMessageTime = DateTime.now();
      _messageCount = 0;

      // Send a test message if debug mode is on
      if (_debugMode) {
        _sendTestMessage();
      }
    } catch (e) {
      print('Error subscribing to topics: $e');
    }
  }

  // Send a test message to verify MQTT connection is working
  void _sendTestMessage() {
    try {
      if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
        print('Cannot send test message - not connected');
        return;
      }

      final builder = MqttClientPayloadBuilder();
      builder.addString(
        json.encode({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'message': 'Test message from Flutter app',
          'clientId': _client?.clientIdentifier,
        }),
      );

      print('Sending test message to ${AppConfig.MQTT_METRICS_TOPIC}');
      _client?.publishMessage(
        AppConfig.MQTT_METRICS_TOPIC,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );

      print('Test message sent');
    } catch (e) {
      print('Error sending test message: $e');
    }
  }

  // Publish a test message to verify publish/subscribe
  void _publishTestMessage() {
    try {
      final builder = MqttClientPayloadBuilder();
      final testMessage = jsonEncode({
        'type': 'test',
        'message': 'Connection test from Flutter app',
        'timestamp': DateTime.now().toIso8601String(),
      });

      builder.addString(testMessage);
      print('Publishing test message to: ${AppConfig.MQTT_METRICS_TOPIC}');
      _client!.publishMessage(
        AppConfig.MQTT_METRICS_TOPIC,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    } catch (e) {
      print('Error publishing test message: $e');
    }
  }

  // Handle connection events
  void _onConnected() {
    // Don't update if disposed
    if (!mounted || _isDisposed) return;

    print('Connection status in onConnected: ${_client?.connectionStatus}');
    print('Return code: ${_client?.connectionStatus?.returnCode}');
    print('Connection state: ${_client?.connectionStatus?.state}');

    // Always trust the connection if we've received the onConnected callback
    // and the return code is connectionAccepted
    if (_client?.connectionStatus?.returnCode ==
        MqttConnectReturnCode.connectionAccepted) {
      _connectionState = MqttConnectionState.connected;
      try {
        _connectionStateController.add(_connectionState);
      } catch (e) {
        print('Error updating connection state: $e');
        return;
      }
      print('MQTT Connected');

      // Setup message listener
      _client!.updates?.listen(_onMessage);

      // Subscribe to topics immediately on successful connection
      _subscribeToTopics();
    } else {
      print('MQTT Connected callback triggered but connection not valid');
      print('Return code: ${_client?.connectionStatus?.returnCode}');
      _connectionState = MqttConnectionState.error;
      try {
        _connectionStateController.add(_connectionState);
      } catch (e) {
        print('Error updating connection state: $e');
        return;
      }
      _scheduleReconnect();
    }
  }

  void _onDisconnected() {
    // Don't update if disposed
    if (!mounted || _isDisposed) return;

    _connectionState = MqttConnectionState.disconnected;
    try {
      _connectionStateController.add(_connectionState);
    } catch (e) {
      print('Error updating connection state: $e');
      return;
    }
    print('MQTT Disconnected');

    // Try to reconnect after a delay if widget is still mounted
    if (mounted && !_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _onSubscribed(String topic) {
    print('MQTT Subscribed to: $topic');
  }

  // Process incoming MQTT messages
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final recMess = message.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      // Update message tracking for UI
      if (mounted) {
        setState(() {
          _lastMessageTime = DateTime.now();
          _messageCount++;
          _lastTopic = message.topic;
        });
      }

      print('MQTT Message received on topic ${message.topic}: $payload');

      try {
        final data = jsonDecode(payload);
        if (data is Map<String, dynamic>) {
          print('Parsed JSON data: $data');
          _updateMetrics(data);
        } else {
          print('Error: Expected a JSON object but got: $data');
        }
      } catch (e) {
        print('Error parsing MQTT message: $e');
        print('Raw payload: $payload');
      }
    }
  }

  // Update metrics from MQTT data
  void _updateMetrics(Map<String, dynamic> data) {
    // Print incoming data types for debugging
    print('Updating metrics with:');
    data.forEach((key, value) {
      print('  $key: $value (${value.runtimeType})');
    });

    // Handle speed from car-board
    double? speed;
    if (data.containsKey('speed')) {
      if (data['speed'] is num) {
        speed = (data['speed'] as num).toDouble();
      } else {
        speed = double.tryParse(data['speed'].toString());
      }
    }

    // Map battery from car-board to energy
    double? energy;
    if (data.containsKey('battery')) {
      if (data['battery'] is num) {
        energy = (data['battery'] as num).toDouble();
      } else {
        energy = double.tryParse(data['battery'].toString());
      }
    } else if (data.containsKey('energy')) {
      if (data['energy'] is num) {
        energy = (data['energy'] as num).toDouble();
      } else {
        energy = double.tryParse(data['energy'].toString());
      }
    }

    // Handle temperature and humidity
    double? temperature;
    if (data.containsKey('temperature')) {
      if (data['temperature'] is num) {
        temperature = (data['temperature'] as num).toDouble();
      } else {
        temperature = double.tryParse(data['temperature'].toString());
      }
    }

    double? humidity;
    if (data.containsKey('humidity')) {
      if (data['humidity'] is num) {
        humidity = (data['humidity'] as num).toDouble();
      } else {
        humidity = double.tryParse(data['humidity'].toString());
      }
    }

    // Check for simulated flag
    final bool isSimulated = data['simulated'] == true;
    if (isSimulated) {
      print('Note: Received simulated sensor data');
    }

    // Update metrics only if we got valid data
    final updatedMetrics = _metrics.copyWith(
      speed: speed ?? _metrics.speed,
      energy: energy ?? _metrics.energy,
      temperature: temperature ?? _metrics.temperature,
      humidity: humidity ?? _metrics.humidity,
    );

    if (mounted && !_isDisposed) {
      setState(() {
        _metrics = updatedMetrics;
      });

      try {
        _metricsController.add(updatedMetrics);
      } catch (e) {
        print('Error adding to metrics controller: $e');
      }

      print(
        'Metrics updated: speed=${_metrics.speed}, energy=${_metrics.energy}, '
        'temp=${_metrics.temperature}, humidity=${_metrics.humidity}',
      );
    }
  }

  @override
  void dispose() {
    // Set disposed flag first to prevent further event handling
    _isDisposed = true;

    // Disconnect MQTT first
    _disconnectMqtt();

    // Cancel all subscriptions
    _metricsSubscription.cancel();
    _connectionSubscription.cancel();

    // Close stream controllers
    _metricsController.close();
    _connectionStateController.close();

    super.dispose();
  }

  // Disconnect MQTT
  void _disconnectMqtt() {
    try {
      if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
        _client!.disconnect();
      }
      // Don't update streams here, they might be closed already
    } catch (e) {
      print('Error disconnecting MQTT: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [_buildConnectionStatusIcon()],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Connection status indicator with extra info
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _getConnectionColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _debugMode = !_debugMode;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _debugMode
                                ? 'Debug mode enabled'
                                : 'Debug mode disabled',
                          ),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    });
                  },
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getConnectionIcon(),
                            color: _getConnectionColor(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getConnectionText(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getConnectionColor(),
                            ),
                          ),
                        ],
                      ),
                      if (_connectionState == MqttConnectionState.connected)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Broker: $_brokerAddress:$_port',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Last message received indicator
              _buildLastMessageIndicator(),

              // Debug controls
              if (_debugMode) _buildDebugControls(),

              const SizedBox(height: 20),

              // Speed display
              Text(
                'SPEED',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _metrics.speed.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const Text(
                    ' km/h',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              // Speed progress bar
              Container(
                width: MediaQuery.of(context).size.width - 64, // Adjusted width
                height: 8,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Container(
                      width:
                          (MediaQuery.of(context).size.width - 64) *
                          (_metrics.speed / AppConfig.PROGRESS_BAR_MAX_SPEED)
                              .clamp(0.0, 1.0),
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Energy display
              Text(
                'ENERGY',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _metrics.energy.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: _getEnergyColor(_metrics.energy),
                    ),
                  ),
                  Text(
                    ' %',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: _getEnergyColor(_metrics.energy),
                    ),
                  ),
                ],
              ),
              // Energy progress bar
              Container(
                width: MediaQuery.of(context).size.width - 64, // Adjusted width
                height: 8,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Container(
                      width:
                          (MediaQuery.of(context).size.width - 64) *
                          (_metrics.energy / 100).clamp(0.0, 1.0),
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getEnergyColor(_metrics.energy),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Add temperature and humidity display
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Temperature card
                  _buildEnvironmentCard(
                    title: 'TEMPERATURE',
                    value: _metrics.temperature.toStringAsFixed(1),
                    unit: '°C',
                    icon: Icons.thermostat,
                    color: _getTemperatureColor(_metrics.temperature),
                  ),

                  // Humidity card
                  _buildEnvironmentCard(
                    title: 'HUMIDITY',
                    value: _metrics.humidity.toStringAsFixed(0),
                    unit: '%',
                    icon: Icons.water_drop,
                    color: Colors.blue,
                  ),
                ],
              ),

              // Add some bottom padding to avoid overflow
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Build environment metrics card
  Widget _buildEnvironmentCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: (MediaQuery.of(context).size.width * 0.42).clamp(
        100.0,
        double.infinity,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getEnergyColor(double energy) {
    if (energy > AppConfig.MEDIUM_ENERGY_THRESHOLD) return Colors.green;
    if (energy > AppConfig.LOW_ENERGY_THRESHOLD) return Colors.orange;
    return Colors.red;
  }

  Widget _buildConnectionStatusIcon() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Icon(_getConnectionIcon(), color: _getConnectionColor()),
    );
  }

  IconData _getConnectionIcon() {
    switch (_connectionState) {
      case MqttConnectionState.connected:
        return Icons.cloud_done;
      case MqttConnectionState.connecting:
        return Icons.cloud_upload;
      case MqttConnectionState.disconnected:
        return Icons.cloud_off;
      case MqttConnectionState.error:
        return Icons.error;
    }
  }

  Color _getConnectionColor() {
    switch (_connectionState) {
      case MqttConnectionState.connected:
        return Colors.green;
      case MqttConnectionState.connecting:
        return Colors.orange;
      case MqttConnectionState.disconnected:
        return Colors.grey;
      case MqttConnectionState.error:
        return Colors.red;
    }
  }

  String _getConnectionText() {
    switch (_connectionState) {
      case MqttConnectionState.connected:
        return 'MQTT CONNECTED';
      case MqttConnectionState.connecting:
        return 'CONNECTING...';
      case MqttConnectionState.disconnected:
        return 'DISCONNECTED';
      case MqttConnectionState.error:
        return 'CONNECTION ERROR';
    }
  }

  Color _getTemperatureColor(double temperature) {
    if (temperature < 15) return Colors.blue; // Cold
    if (temperature < 25) return Colors.green; // Normal
    if (temperature < 35) return Colors.orange; // Warm
    return Colors.red; // Hot
  }

  Widget _buildLastMessageIndicator() {
    // Style for the message indicator
    final baseTextStyle = TextStyle(fontSize: 12, color: Colors.grey.shade700);

    final highlightTextStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Colors.blue.shade700,
    );

    // Calculate time since last message
    String timeStatus;
    Color statusColor;

    if (_lastMessageTime == null) {
      timeStatus = "No messages received";
      statusColor = Colors.grey;
    } else {
      final difference = DateTime.now().difference(_lastMessageTime!);

      if (difference.inSeconds < 10) {
        timeStatus = "Just now";
        statusColor = Colors.green;
      } else if (difference.inMinutes < 1) {
        timeStatus = "${difference.inSeconds} seconds ago";
        statusColor = Colors.green;
      } else if (difference.inMinutes < 5) {
        timeStatus = "${difference.inMinutes} minutes ago";
        statusColor = Colors.orange;
      } else {
        timeStatus = "${difference.inMinutes} minutes ago";
        statusColor = Colors.red;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Last message: $timeStatus",
            style: baseTextStyle.copyWith(color: statusColor),
          ),
          const SizedBox(height: 4),
          if (_lastTopic.isNotEmpty) ...[
            Row(
              children: [
                Text("Topic: ", style: baseTextStyle),
                Text(_lastTopic, style: highlightTextStyle),
              ],
            ),
            const SizedBox(height: 2),
          ],
          Text("Total messages: $_messageCount", style: baseTextStyle),
        ],
      ),
    );
  }

  // Debug controls
  Widget _buildDebugControls() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _handleManualReconnection,
          child: Text('Reconnect to MQTT'),
        ),
        ElevatedButton(
          onPressed: _handleManualMessagePublish,
          child: Text('Publish Manual Message'),
        ),
      ],
    );
  }

  void _handleManualReconnection() {
    // Implement manual reconnection logic here
    print('Manual reconnection requested');
    _setupMqttConnection();
  }

  void _handleManualMessagePublish() {
    // Implement manual message publishing logic here
    print('Manual message publishing requested');
    _publishTestMessage();
  }
}
