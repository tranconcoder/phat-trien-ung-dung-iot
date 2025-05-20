import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ControlPanelScreen extends StatefulWidget {
  const ControlPanelScreen({Key? key}) : super(key: key);

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen> {
  // Socket.IO client
  late IO.Socket socket;

  // Connection state
  bool _isConnected = false;
  bool _isInitialized = false;
  bool _mainImageError = false;
  bool _isConnecting = true;
  bool _isSendingCommand = false; // Track command sending state
  String _lastCommand = ""; // Track last command sent
  Timer? _connectionTimer;

  // Car board IP configuration
  String _carIpAddress = "192.168.1.12"; // Default value
  final TextEditingController _ipController =
      TextEditingController(text: "192.168.1.12");

  // WebSocket IP configuration
  String _websocketIpAddress = ""; // Will be initialized from AppConfig
  final TextEditingController _wsIpController = TextEditingController();

  // Image data
  Uint8List? _mainImageBytes;
  DateTime _lastImageUpdate = DateTime.now();

  // MQTT client for turn signals
  MqttServerClient? _mqttClient;
  final bool _isMqttConnected = false;

  // Turn signal states
  final bool _isLeftSignalOn = false;
  final bool _isRightSignalOn = false;

  @override
  void initState() {
    super.initState();
    // Initialize websocket IP from config
    _websocketIpAddress = AppConfig.SOCKETIO_URL
        .replaceAll('http://', '')
        .replaceAll(':4001', '');
    _wsIpController.text = _websocketIpAddress;

    // Load saved IPs
    Future.wait([_loadCarIp(), _loadWsIp()]).then((_) {
      _initializeSocketConnection();
    });
  }

  void _initializeSocketConnection() {
    try {
      // Initialize Socket.IO connection using app config or saved IP
      final socketIoUrl = 'http://$_websocketIpAddress:4001';
      debugPrint('Connecting to Socket.IO server: $socketIoUrl');

      socket = IO.io(socketIoUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'connectTimeout': AppConfig.SOCKETIO_CONNECT_TIMEOUT,
        'reconnectionDelay': AppConfig.SOCKETIO_RECONNECT_DELAY,
      });

      // Register event handlers
      _registerSocketEventHandlers();

      // Initial connection attempt
      socket.connect();

      // Add a fallback timer that will show error UI if connection takes too long
      _connectionTimer = Timer(const Duration(seconds: 5), () {
        if (!_isConnected && mounted) {
          setState(() {
            _mainImageError = true;
            _isConnecting = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing Socket.IO: $e');
      setState(() {
        _mainImageError = true;
        _isConnecting = false;
        _isInitialized = true;
      });
    }
  }

  void _reconnectSocket() {
    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _isConnecting = true;
    });

    _connectionTimer?.cancel();

    try {
      // Reconnect to socket
      if (socket.disconnected) {
        socket.connect();
      } else {
        socket.disconnect();
        // Wait a moment before reconnecting
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) socket.connect();
        });
      }

      // Set a new timeout
      _connectionTimer = Timer(const Duration(seconds: 5), () {
        if (!_isConnected && mounted) {
          setState(() {
            _mainImageError = true;
            _isConnecting = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error reconnecting: $e');
      if (mounted) {
        setState(() {
          _mainImageError = true;
          _isConnecting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    _ipController.dispose();
    _wsIpController.dispose();

    // Disconnect MQTT client
    _mqttClient?.disconnect();

    // Disconnect and dispose socket
    try {
      socket.disconnect();
      socket.dispose();
    } catch (e) {
      debugPrint('Error disposing socket: $e');
    }

    super.dispose();
  }

  // Control methods
  void _sendControlCommand(String direction) {
    // Set last command
    setState(() {
      _lastCommand = direction;
    });

    // Show feedback immediately for better UX
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lệnh: $direction'),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Set sending state
    setState(() {
      _isSendingCommand = true;
    });

    // Construct the URL to the ESP32 HTTP server
    final url = 'http://$_carIpAddress/$direction';

    // Send the HTTP request directly to the car-board ESP32
    debugPrint('Sending HTTP request to: $url');
    http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 3), // Timeout after 3 seconds
      onTimeout: () {
        setState(() {
          _isSendingCommand = false;
        });
        debugPrint('Request timed out');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lỗi: Yêu cầu đã hết thời gian chờ'),
            backgroundColor: Colors.red,
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
        throw TimeoutException('Request timed out');
      },
    ).then((response) {
      setState(() {
        _isSendingCommand = false;
      });
      if (response.statusCode == 200) {
        debugPrint('Command sent successfully: ${response.body}');
      } else {
        debugPrint(
            'Error sending command. Status code: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: Mã trạng thái ${response.statusCode}'),
            backgroundColor: Colors.red,
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }).catchError((error) {
      setState(() {
        _isSendingCommand = false;
      });
      debugPrint('Error sending command: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi kết nối: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  // Shows a dialog to configure car IP address
  void _showCarIpDialog() {
    // Update controller with current value
    _ipController.text = _carIpAddress;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cài đặt IP', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ IP xe',
                hintText: 'Ví dụ: 192.168.1.12',
                labelStyle: TextStyle(fontSize: 14),
                hintStyle: TextStyle(fontSize: 12),
              ),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wsIpController,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ IP WebSocket',
                hintText: 'Ví dụ: 192.168.1.10',
                labelStyle: TextStyle(fontSize: 14),
                hintStyle: TextStyle(fontSize: 12),
              ),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              final newCarIp = _ipController.text.trim();
              final newWsIp = _wsIpController.text.trim();

              if (newCarIp.isNotEmpty) {
                setState(() => _carIpAddress = newCarIp);
                _saveCarIp(newCarIp);
              }

              if (newWsIp.isNotEmpty && newWsIp != _websocketIpAddress) {
                setState(() => _websocketIpAddress = newWsIp);
                _saveWsIp(newWsIp);

                // Reconnect to new WebSocket server
                _reconnectToNewWsServer(newWsIp);
              }

              Navigator.pop(context);
            },
            child: const Text('Lưu', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // Save WebSocket IP to shared preferences
  Future<void> _saveWsIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('websocket_ip_address', ip);
      debugPrint('WebSocket IP saved: $ip');
    } catch (e) {
      debugPrint('Error saving WebSocket IP: $e');
    }
  }

  // Load WebSocket IP from shared preferences
  Future<void> _loadWsIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('websocket_ip_address');
      if (savedIp != null && savedIp.isNotEmpty) {
        setState(() {
          _websocketIpAddress = savedIp;
          _wsIpController.text = savedIp;
        });
        debugPrint('Loaded WebSocket IP: $savedIp');
      }
    } catch (e) {
      debugPrint('Error loading WebSocket IP: $e');
    }
  }

  // Reconnect to new WebSocket server
  void _reconnectToNewWsServer(String newIp) {
    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _isConnecting = true;
      _mainImageError = false;
    });

    try {
      // Disconnect from current socket
      socket.disconnect();

      // Create new Socket.IO URL
      final newSocketIoUrl = 'http://$newIp:4001';
      debugPrint('Connecting to new Socket.IO URL: $newSocketIoUrl');

      // Initialize new Socket.IO connection
      socket = IO.io(newSocketIoUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'connectTimeout': AppConfig.SOCKETIO_CONNECT_TIMEOUT,
        'reconnectionDelay': AppConfig.SOCKETIO_RECONNECT_DELAY,
      });

      // Re-register all event handlers
      _registerSocketEventHandlers();

      // Connect to the new server
      socket.connect();

      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kết nối tới: $newSocketIoUrl'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error reconnecting to new WebSocket server: $e');
      setState(() {
        _mainImageError = true;
        _isConnecting = false;
      });
    }
  }

  // Register Socket.IO event handlers
  void _registerSocketEventHandlers() {
    socket.onConnect((_) {
      debugPrint('Socket.IO connected');
      if (mounted) {
        setState(() {
          _isConnected = true;
          _isInitialized = true;
          _isConnecting = false;
          _mainImageError = false;
        });

        // Request latest front camera image
        _requestFrontCamImage();
      }
    });

    socket.onDisconnect((_) {
      debugPrint('Socket.IO disconnected');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _mainImageError = true;
        });
      }
    });

    // Receive ESP32 camera images (from /frontcam)
    socket.on('frontcam', (data) {
      if (!mounted) return;
      try {
        if (data is Uint8List) {
          debugPrint('Received ESP32 frontcam data: ${data.length} bytes');

          setState(() {
            _mainImageBytes = data;
            _lastImageUpdate = DateTime.now();
          });
        }
      } catch (e) {
        debugPrint('Error processing ESP32 camera image: $e');
      }
    });

    // Socket.IO event handlers for other features
    socket.on('command_received', (data) {
      debugPrint('Command received confirmation: $data');
    });

    socket.on('message', (data) {
      debugPrint('Server message: $data');
    });

    socket.onError((error) {
      debugPrint('Socket.IO error: $error');
      if (mounted) {
        setState(() {
          _mainImageError = true;
          _isConnecting = false;
        });
      }
    });
  }

  // Request front camera image from server
  void _requestFrontCamImage() {
    if (!_isConnected) return;

    try {
      debugPrint('Requesting front camera image from server');
      socket.emit('frontcam');
    } catch (e) {
      debugPrint('Error requesting front camera image: $e');
    }
  }

  // Save car IP to shared preferences
  Future<void> _saveCarIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('car_ip_address', ip);
      debugPrint('Car IP saved: $ip');
    } catch (e) {
      debugPrint('Error saving car IP: $e');
    }
  }

  // Load car IP from shared preferences
  Future<void> _loadCarIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('car_ip_address');
      if (savedIp != null && savedIp.isNotEmpty) {
        setState(() {
          _carIpAddress = savedIp;
          _ipController.text = savedIp;
        });
        debugPrint('Loaded car IP: $savedIp');
      }
    } catch (e) {
      debugPrint('Error loading car IP: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Điều KHiển Xe',
              style: TextStyle(
                fontSize: 16, // Smaller font to prevent overflow
              ),
            ),
            const SizedBox(width: 6), // Reduced size
            _isConnected
                ? const Icon(Icons.wifi, color: Colors.green, size: 16)
                : _isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_off, color: Colors.red, size: 16),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Cài đặt IP',
            onPressed: _showCarIpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới kết nối',
            onPressed: _reconnectSocket,
          ),
        ],
      ),
      body: _buildControlPanel(),
    );
  }

  Widget _buildControlPanel() {
    return Stack(
      children: [
        // Main layout - Wrap the Column with SingleChildScrollView
        SingleChildScrollView(
          physics:
              const BouncingScrollPhysics(), // Optional: Nice scroll physics
          child: Column(
            children: [
              // Main camera - full width 16:9
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _mainImageError
                    ? _buildImageErrorPlaceholder()
                    : _buildMainImageView(),
              ),

              // Car IP display
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Car IP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.car_crash,
                            size: 10, color: Colors.blue),
                        const SizedBox(width: 2),
                        Text(
                          'Xe: $_carIpAddress',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    // WebSocket IP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi, size: 10, color: Colors.green),
                        const SizedBox(width: 2),
                        Text(
                          'WS: $_websocketIpAddress',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: _showCarIpDialog,
                          child: const Icon(
                            Icons.edit,
                            size: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Add a thin divider
              Divider(
                color: Colors.grey.withOpacity(0.3),
                thickness: 1,
                height: 8,
              ),

              // Control container with fixed height to prevent overflow
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = MediaQuery.of(context).size.height;
                  final appBarHeight = AppBar().preferredSize.height;
                  final statusBarHeight = MediaQuery.of(context).padding.top;
                  const ipDisplayHeight =
                      40.0; // Approximate height of IP display

                  // Calculate max safe height for controls
                  final safeHeight = availableHeight -
                      appBarHeight -
                      statusBarHeight -
                      ipDisplayHeight -
                      15.0;

                  return Container(
                    constraints: BoxConstraints(
                      maxHeight: safeHeight,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 60),
                        child: _buildDirectionalControls(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainImageView() {
    // Calculate time since last frame update for connection status
    final timeSinceUpdate =
        DateTime.now().difference(_lastImageUpdate).inSeconds;
    final isStale = timeSinceUpdate > 5; // Consider image stale after 5 seconds

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Display actual image if available, otherwise show placeholder
          if (_mainImageBytes != null)
            Image.memory(
              _mainImageBytes!,
              fit: BoxFit.contain,
              gaplessPlayback: true, // For smoother updates
            )
          else if (_isConnecting)
            // Loading indicator while connecting
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Đang kết nối camera...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          else
            // Default message when not connected and not connecting
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image,
                    size: 80,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Waiting for camera feed...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // Show warning if image is stale
          if (isStale && _isConnected)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Cập nhật chậm ($timeSinceUpdate giây)',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // Show connection status indicator
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isConnected
                    ? Colors.green.withOpacity(0.7)
                    : _isConnecting
                        ? Colors.amber.withOpacity(0.7)
                        : Colors.red.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _isConnected
                    ? 'Connected'
                    : _isConnecting
                        ? 'Connecting...'
                        : 'Disconnected',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),

          // Add refresh button
          if (_isConnected)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  _requestFrontCamImage();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing camera image...'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectionalControls() {
    // Use MediaQuery to make the control size responsive to screen size
    final screenSize = MediaQuery.of(context).size;
    // Calculate a base size that scales with screen width (within reasonable limits)
    final double baseSize = (screenSize.width * 0.15).clamp(40.0, 60.0);
    // Calculate spacing based on screen width
    final double horizontalSpacing = (screenSize.width * 0.02).clamp(5.0, 15.0);
    // Calculate vertical spacing based on screen width or a fraction of base size
    final double verticalSpacing = baseSize * 0.1;

    return Padding(
      // Reduced horizontal padding to give controls more space
      padding: const EdgeInsets.symmetric(horizontal: 5.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Last command indicator (keep existing style)
          if (_lastCommand.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, size: 10, color: Colors.blue),
                  const SizedBox(width: 2),
                  Text(
                    'Lệnh: $_lastCommand',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: verticalSpacing), // Dynamic vertical spacing

          // Forward button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                icon: Icons.arrow_upward,
                onPressed: () => _sendControlCommand('forward'),
                color: Colors.green,
                size: baseSize, // Use scaled base size
              ),
            ],
          ),
          SizedBox(height: verticalSpacing), // Dynamic vertical spacing

          // Left, Stop, Right buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                icon: Icons.arrow_back,
                onPressed: () => _sendControlCommand('left'),
                color: Colors.orange,
                size: baseSize, // Use scaled base size
              ),
              SizedBox(width: horizontalSpacing), // Dynamic horizontal spacing
              _buildControlButton(
                icon: Icons.stop_circle_outlined,
                onPressed: () => _sendControlCommand('stop'),
                color: Colors.red,
                size: baseSize * 1.2, // Stop button slightly larger
              ),
              SizedBox(width: horizontalSpacing), // Dynamic horizontal spacing
              _buildControlButton(
                icon: Icons.arrow_forward,
                onPressed: () => _sendControlCommand('right'),
                color: Colors.orange,
                size: baseSize, // Use scaled base size
              ),
            ],
          ),
          SizedBox(height: verticalSpacing), // Dynamic vertical spacing

          // Backward button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                icon: Icons.arrow_downward,
                onPressed: () => _sendControlCommand('backward'),
                color: Colors.blue,
                size: baseSize, // Use scaled base size
              ),
            ],
          ),

          // LED/Relay control
          SizedBox(height: verticalSpacing * 2), // More space before LED
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                icon: Icons.lightbulb,
                onPressed: () => _sendControlCommand('led/on'),
                color: Colors.amber,
                size: baseSize * 0.8, // LED buttons smaller
              ),
              SizedBox(width: horizontalSpacing * 1.5), // More space for LED
              _buildControlButton(
                icon: Icons.lightbulb_outline,
                onPressed: () => _sendControlCommand('led/off'),
                color: Colors.grey,
                size: baseSize * 0.8, // LED buttons smaller
              ),
            ],
          ),
          // Text label for LED controls
          const Padding(
            padding: EdgeInsets.only(top: 2.0),
            child: Text(
              'Đèn LED',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 9,
              ),
            ),
          ),
          SizedBox(height: verticalSpacing), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.blue,
    double size = 56,
  }) {
    return Container(
      margin: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        color: color.withOpacity(_isSendingCommand ? 0.1 : 0.2),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSendingCommand ? null : onPressed, // Disable when sending
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: _isSendingCommand
                ? Center(
                    child: SizedBox(
                      width: size * 0.4,
                      height: size * 0.4,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    color: color,
                    size: size * 0.45,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 32,
            ),
            const SizedBox(height: 8),
            const Text(
              'Không thể kết nối camera',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _reconnectSocket,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
