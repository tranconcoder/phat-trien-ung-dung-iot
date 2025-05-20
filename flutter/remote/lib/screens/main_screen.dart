import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'driver_camera_tab.dart';
import 'gps_mqtt_screen.dart';
// import 'settings_screen.dart'; // Removed
import 'control_panel_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1; // Default to the control panel screen

  // List of screens/pages we can navigate to
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _screens = [
      const GpsMqttScreen(),
      const ControlPanelScreen(),
      const DriverCameraTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed, // Required for more than 3 items
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'GPS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.drive_eta),
            label: 'Điều khiển',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.face),
            label: 'Driver Cam',
          ),
          // BottomNavigationBarItem( // Removed
          //   icon: Icon(Icons.settings),
          //   label: 'Cài đặt',
          // ),
        ],
      ),
    );
  }
}
