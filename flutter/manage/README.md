# Quản Lý Giao Thông

A Flutter application for transportation management and monitoring.

## Features

- Real-time vehicle metrics monitoring via MQTT
- Dashboard for speed and energy visualization
- Support for location tracking and mapping

## Configuration

The application uses centralized configuration in the `lib/config/app_config.dart` file. Key configuration parameters include:

### MQTT Configuration

- `MQTT_HOST`: MQTT broker host address
- `MQTT_PORT`: MQTT broker port (default: 8883)
- `MQTT_USE_TLS`: Whether to use TLS encryption (default: true)
- `MQTT_VEHICLE_TOPIC`: Topic prefix for vehicle data (default: "vehicle1")
- `MQTT_KEEP_ALIVE`: MQTT connection keep-alive period in seconds
- `MQTT_RECONNECT_DELAY`: Time to wait before reconnection attempts

### Map Configuration

- `DEFAULT_MAP_ZOOM`: Default zoom level for maps
- `DEFAULT_LATITUDE` & `DEFAULT_LONGITUDE`: Default map center coordinates

### UI Configuration

- `PROGRESS_BAR_MAX_SPEED`: Maximum speed for progress bar visualization
- `LOW_ENERGY_THRESHOLD` & `MEDIUM_ENERGY_THRESHOLD`: Thresholds for energy level visualization

### Application Configuration

- `APP_NAME`: The application name
- `APP_VERSION`: The application version number

## Getting Started

1. Clone the repository
2. Update the configuration in `lib/config/app_config.dart` as needed
3. Run `flutter pub get` to install dependencies
4. Connect to your MQTT broker or use the simulation mode for testing
5. Run the application with `flutter run`

## MQTT Topics

The application subscribes to the following topics:

- `vehicle/{id}/speed`: Vehicle speed in km/h
- `vehicle/{id}/energy`: Vehicle energy level in percentage
- `vehicle/{id}/consumption`: Energy consumption rate
- `vehicle/{id}/location`: Vehicle location (JSON with lat/lng)
- `vehicle/{id}/metrics`: Comprehensive vehicle metrics (JSON)

## Requirements

- Flutter 3.0+
- Dart 2.17+
- Internet connection for MQTT broker access

## License

MIT
