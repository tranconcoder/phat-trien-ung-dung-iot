class AppConfig {
  // MQTT Configuration
  // ignore: constant_identifier_names
  static const String MQTT_HOST = 'fd66ecb3.ala.asia-southeast1.emqxsl.com';
  static const int MQTT_PORT = 8883;
  static const bool MQTT_USE_TLS = true;

  // Fallback MQTT brokers if primary fails
  static const String MQTT_FALLBACK_HOST =
      '151.106.112.215'; // Direct IP fallback
  static const int MQTT_FALLBACK_PORT = 1883;
  static const bool MQTT_FALLBACK_USE_TLS = false;

  // Public MQTT broker for worst-case scenario
  static const String MQTT_PUBLIC_HOST = 'broker.emqx.io';
  static const int MQTT_PUBLIC_PORT = 1883;

  // The metrics topic should match the one used in car-board.ino
  static const String MQTT_METRICS_TOPIC = '/metrics';
  static const String MQTT_VEHICLE_TOPIC =
      '/metrics'; // Changed to match car-board

  static const int MQTT_KEEP_ALIVE = 30;
  static const int MQTT_RECONNECT_DELAY = 5; // seconds
  static const String MQTT_USERNAME = 'trancon2';
  static const String MQTT_PASSWORD = '123';

  // Map Configuration
  static const double DEFAULT_MAP_ZOOM = 15.0;
  static const double DEFAULT_LATITUDE = 10.823099; // Ho Chi Minh City
  static const double DEFAULT_LONGITUDE = 106.629662;

  // UI Configuration
  static const double PROGRESS_BAR_MAX_SPEED = 120.0; // km/h
  static const double LOW_ENERGY_THRESHOLD = 20.0; // %
  static const double MEDIUM_ENERGY_THRESHOLD = 50.0; // %

  // Application Configuration
  static const String APP_NAME = 'Quản Lý Giao Thông';
  static const String APP_VERSION = '1.0.0';

  // Server Configuration
  static const String SERVER_URL = 'http://192.168.1.101:4000';
}
