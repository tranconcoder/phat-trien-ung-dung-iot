import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/app_config.dart';

class MqttService {
  MqttServerClient? _client;
  final String clientId;
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
      : clientId = id ?? 'flutter_app_${DateTime.now().millisecondsSinceEpoch}';

  // Initialize and connect
  Future<bool> connect() async {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      return true;
    }

    _client = MqttServerClient.withPort(
      AppConfig.MQTT_HOST,
      clientId,
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
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atLeastOnce)
        .authenticateAs(AppConfig.MQTT_USERNAME, AppConfig.MQTT_PASSWORD);

    _client!.connectionMessage = connMessage;

    // Connect to the broker
    try {
      await _client!.connect();
      return _connected;
    } catch (e) {
      debugPrint('Exception: $e');
      _client!.disconnect();
      return false;
    }
  }

  // Publish message to a topic
  void publishMessage(String topic, String message) {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    }
  }

  // Publish GPS location to the designated topic
  void publishLocationData(
    double latitude,
    double longitude, {
    double? speed,
    double? heading,
  }) {
    final Map<String, dynamic> locationData = {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Add optional data if available
    if (speed != null) locationData['speed'] = speed;
    if (heading != null) locationData['heading'] = heading;

    // Convert to JSON string and publish
    final String jsonData = jsonEncode(locationData);
    publishMessage(AppConfig.MQTT_GPS_TOPIC, jsonData);
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

    // Close the stream controllers if they're not already closed
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

    // Check if the stream is still open before adding events
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(true);
    }

    debugPrint('MQTT client connected');

    // Set up the message handler
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final MqttReceivedMessage<MqttMessage> message in messages) {
        final MqttPublishMessage recMess =
            message.payload as MqttPublishMessage;
        final String topic = message.topic;

        final String messagePayload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );

        // Only process if message controller is still open
        if (!_messageController.isClosed) {
          try {
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

    // Check if the stream is still open before adding events
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(false);
    }

    debugPrint('MQTT client disconnected');

    // Try to reconnect after a delay
    Future.delayed(const Duration(seconds: AppConfig.MQTT_RECONNECT_DELAY), () {
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
