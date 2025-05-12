import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/app_config.dart';

class MqttService {
  MqttServerClient? _client;
  final String id;
  bool _connected = false;

  // Stream controllers to pass data around
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Connection status controller
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  MqttService({String? id})
    : id = id ?? 'flutter_map_client_${DateTime.now().millisecondsSinceEpoch}';

  // Initialize and connect
  Future<bool> connect() async {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      return true;
    }

    _client = MqttServerClient.withPort(
      AppConfig.MQTT_HOST,
      id,
      AppConfig.MQTT_PORT,
    );

    // Set secure connection if TLS is enabled
    if (AppConfig.MQTT_USE_TLS) {
      _client!.secure = true;
      _client!.securityContext = SecurityContext.defaultContext;
      // You might need to add certificates if using self-signed
      // _client.securityContext.setTrustedCertificates('path_to_cert');
    }

    _client!.keepAlivePeriod = AppConfig.MQTT_KEEP_ALIVE;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.onSubscribeFail = _onSubscribeFail;
    _client!.pongCallback = _pong;

    // Set the correct MQTT protocol for the port
    _client!.setProtocolV311();

    // Setup connection message with authentication
    final connMessage = MqttConnectMessage()
        .withWillRetain()
        .withClientIdentifier(id)
        .withWillQos(MqttQos.atLeastOnce);

    // Add authentication if credentials are provided
    if (AppConfig.MQTT_USERNAME.isNotEmpty &&
        AppConfig.MQTT_PASSWORD.isNotEmpty) {
      connMessage.authenticateAs(
        AppConfig.MQTT_USERNAME,
        AppConfig.MQTT_PASSWORD,
      );
    }

    _client!.connectionMessage = connMessage;

    // Connect to the broker
    try {
      await _client!.connect();
      final MqttConnectionState connectionState =
          _client!.connectionStatus!.state;
      _connected = connectionState == MqttConnectionState.connected;

      if (_connected) {
        // Subscribe to the GPS topic by default
        subscribe(AppConfig.MQTT_GPS_TOPIC);
      } else {
        // If not connected, try fallback options
        await _tryFallbackConnection();
      }

      return _connected;
    } catch (e) {
      debugPrint('MQTT connection exception: $e');
      _client!.disconnect();
      await _tryFallbackConnection();
      return _connected;
    }
  }

  // Try fallback MQTT brokers if the primary one fails
  Future<void> _tryFallbackConnection() async {
    if (_connected) return;

    debugPrint('Trying fallback MQTT broker...');

    // Disconnect from current client if any
    _client?.disconnect();

    // Try fallback broker
    _client = MqttServerClient.withPort(
      AppConfig.MQTT_FALLBACK_HOST,
      id,
      AppConfig.MQTT_FALLBACK_PORT,
    );

    _client!.secure = AppConfig.MQTT_FALLBACK_USE_TLS;
    _client!.keepAlivePeriod = AppConfig.MQTT_KEEP_ALIVE;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.onSubscribeFail = _onSubscribeFail;
    _client!.pongCallback = _pong;
    _client!.setProtocolV311();

    final connMessage = MqttConnectMessage()
        .withWillRetain()
        .withClientIdentifier(id)
        .withWillQos(MqttQos.atLeastOnce);

    if (AppConfig.MQTT_USERNAME.isNotEmpty &&
        AppConfig.MQTT_PASSWORD.isNotEmpty) {
      connMessage.authenticateAs(
        AppConfig.MQTT_USERNAME,
        AppConfig.MQTT_PASSWORD,
      );
    }

    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
      _connected =
          _client!.connectionStatus!.state == MqttConnectionState.connected;

      if (_connected) {
        debugPrint('Connected to fallback MQTT broker');
        subscribe(AppConfig.MQTT_GPS_TOPIC);
      }
    } catch (e) {
      debugPrint('Fallback MQTT connection exception: $e');
      _client!.disconnect();
      _connected = false;
    }
  }

  // Subscribe to a topic
  void subscribe(String topic) {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  // Unsubscribe from a topic
  void unsubscribe(String topic) {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      _client!.unsubscribe(topic);
    }
  }

  // Disconnect from the broker
  void disconnect() {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      _client!.disconnect();
    }
  }

  // Dispose resources
  void dispose() {
    disconnect();

    if (!_messageController.isClosed) {
      _messageController.close();
    }

    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.close();
    }
  }

  // Callback handlers
  void _onConnected() {
    _connected = true;
    debugPrint('Connected to MQTT broker');

    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(true);
    }

    // Set up the message handler
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final MqttReceivedMessage<MqttMessage> message in messages) {
        final MqttPublishMessage recMess =
            message.payload as MqttPublishMessage;
        final String topic = message.topic;

        final String messagePayload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );

        if (!_messageController.isClosed) {
          try {
            // Try to parse as JSON
            final Map<String, dynamic> data = {
              'topic': topic,
              'message': jsonDecode(messagePayload),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
            _messageController.add(data);
          } catch (e) {
            // If not valid JSON, send as string
            final Map<String, dynamic> data = {
              'topic': topic,
              'message': messagePayload,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
            _messageController.add(data);
          }
        }
      }
    });
  }

  void _onDisconnected() {
    _connected = false;
    debugPrint('Disconnected from MQTT broker');

    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(false);
    }

    // Try to reconnect after a delay
    Future.delayed(Duration(seconds: AppConfig.MQTT_RECONNECT_DELAY), () {
      if (!_connected) connect();
    });
  }

  void _onSubscribed(String topic) {
    debugPrint('Subscription confirmed for topic $topic');
  }

  void _onSubscribeFail(String topic) {
    debugPrint('Failed to subscribe to topic $topic');
  }

  void _pong() {
    debugPrint('Ping response received from MQTT broker');
  }

  // Check if connected
  bool get isConnected => _connected;
}
