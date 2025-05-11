import 'package:flutter/material.dart';
import '../config/app_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
      ),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.cloud),
            title: Text('Máy chủ MQTT'),
            subtitle: Text(AppConfig.MQTT_HOST),
          ),
          ListTile(
            leading: Icon(Icons.pin_drop),
            title: Text('Topic GPS'),
            subtitle: Text(AppConfig.MQTT_GPS_TOPIC),
          ),
          ListTile(
            leading: Icon(Icons.timer),
            title: Text('Tần suất gửi'),
            subtitle: Text('${AppConfig.LOCATION_UPDATE_INTERVAL}ms'),
          ),
          ListTile(
            leading: Icon(Icons.info),
            title: Text('Phiên bản'),
            subtitle: Text(AppConfig.APP_VERSION),
          ),
          Divider(),
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Ứng dụng này gửi dữ liệu GPS từ thiết bị di động đến máy chủ MQTT để phục vụ cho hệ thống quản lý giao thông.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
} 