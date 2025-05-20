class AppConfig {
  // MQTT Configuration
  // ignore: constant_identifier_names
  static const String MQTT_HOST = 'fd66ecb3.ala.asia-southeast1.emqxsl.com';
  static const int MQTT_PORT = 8883;
  static const bool MQTT_USE_TLS = true;

  static const String MQTT_GPS_TOPIC = '/gps';
  static const String MQTT_METRICS_TOPIC = '/metrics';
  static const String MQTT_TURN_SIGNALS_TOPIC = '/turn_signals';

  static const int MQTT_KEEP_ALIVE = 30;
  static const int MQTT_RECONNECT_DELAY = 5; // seconds
  static const String MQTT_USERNAME = 'trancon';
  static const String MQTT_PASSWORD = '123';

  // Client IDs
  static const String MQTT_CLIENT_ID_REMOTE = 'flutter_remote_client'; // Added
  static const String MQTT_CLIENT_ID_GPS = 'flutter_gps_client'; // Added

  // Location Service Configuration
  static const int LOCATION_UPDATE_INTERVAL = 1000; // milliseconds (1 second)
  static const int LOCATION_DISTANCE_FILTER =
      0; // meters (0 means update even if position doesn't change)

  // UI Configuration
  static const double PROGRESS_BAR_MAX_SPEED = 120.0; // km/h
  static const double LOW_ENERGY_THRESHOLD = 20.0; // %
  static const double MEDIUM_ENERGY_THRESHOLD = 50.0; // %

  // Application Configuration
  static const String APP_NAME = 'Quản Lý Giao Thông Remote';
  static const String APP_VERSION = '1.0.0';

  // Server Configuration
  static const String SERVER_URL = 'http://192.168.1.92:4001';

  // WebSocket Configuration
  static const String WEBSOCKET_URL = 'ws://192.168.1.92:8887';

  // Socket.IO Configuration
  static const String SOCKETIO_URL = 'http://192.168.1.92:4001';
  static const int SOCKETIO_CONNECT_TIMEOUT =
      20000; // Increased from 10000 to 20000 milliseconds
  static const int SOCKETIO_RECONNECT_DELAY = 5000; // milliseconds
  static const String SOCKETIO_CAMERA_ROOM = 'drivercam';
}
