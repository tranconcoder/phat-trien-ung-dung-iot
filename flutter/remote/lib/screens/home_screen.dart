import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:camera/camera.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  // final _authService = AuthService();
  final PageController _pageController = PageController();

  final List<Widget> _screens = [
    const VehicleTab(),
    const TrafficTab(),
    const MapTab(),
    const ProfileTab(),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey.shade600,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.directions_car_outlined),
                activeIcon: Icon(Icons.directions_car),
                label: 'Vehicle',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.traffic_outlined),
                activeIcon: Icon(Icons.traffic),
                label: 'Traffic',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tab screens

class VehicleTab extends StatefulWidget {
  const VehicleTab({super.key});

  @override
  State<VehicleTab> createState() => _VehicleTabState();
}

class _VehicleTabState extends State<VehicleTab> {
  WebSocketChannel? _channel;
  String _videoUrl = '';
  bool _isConnected = false;

  // Position of front camera (for draggable functionality)
  double _frontCameraX = 0;
  double _frontCameraY = 0;

  // Camera controller
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];

  // Video player controllers for main video feed
  VideoPlayerController? _frontCameraController;
  ChewieController? _frontChewieController;

  @override
  void initState() {
    super.initState();
    _connectToWebSocket();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      // Get available cameras
      _cameras = await availableCameras();

      if (_cameras.isNotEmpty) {
        // Use front camera if available
        final frontCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );

        // Initialize the controller
        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        // Start camera stream
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      print('Error initializing camera: $e');
      // Fallback to video player if camera fails
      _initializeVideoFallback();
    }
  }

  void _initializeVideoFallback() async {
    // Use a sample video as fallback
    const String sampleVideoUrl =
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

    _frontCameraController = VideoPlayerController.network(sampleVideoUrl);
    await _frontCameraController!.initialize();

    _frontChewieController = ChewieController(
      videoPlayerController: _frontCameraController!,
      autoPlay: true,
      looping: true,
      aspectRatio: 3 / 4,
      showControls: false,
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _connectToWebSocket() {
    try {
      // Replace with your WebSocket server URL
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://your-websocket-server-url'),
      );
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'video') {
            setState(() {
              _videoUrl = data['url'];
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          }
        },
      );

      setState(() {
        _isConnected = true;
      });
    } catch (e) {
      print('WebSocket connection error: $e');
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _sendCommand(String command) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode({'command': command}));
    }
  }

  @override
  void dispose() {
    _frontCameraController?.dispose();
    _frontChewieController?.dispose();
    _cameraController?.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Control'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content column (everything except draggable front camera)
            Column(
              children: [
                // Connection status indicator
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  alignment: Alignment.centerRight,
                  child:
                      _isConnected
                          ? const Icon(Icons.wifi, color: Colors.green)
                          : TextButton.icon(
                            onPressed: _connectToWebSocket,
                            icon: const Icon(Icons.wifi_off, color: Colors.red),
                            label: const Text(
                              'Reconnect',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                ),

                // Video Display Area (main camera)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Set main video URL if empty
                      if (_videoUrl.isEmpty) {
                        _videoUrl =
                            'https://via.placeholder.com/640x360?text=Main+Camera';
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child:
                                  _videoUrl.isNotEmpty
                                      ? Image.network(
                                        _videoUrl,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      )
                                      : const Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.videocam_off,
                                              size: 48,
                                              color: Colors.white54,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Waiting...',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Control Buttons - Larger size, evenly spaced horizontally
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16,
                  ), // More bottom padding
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate button dimensions - larger buttons with equal size
                      final buttonWidth =
                          constraints.maxWidth * 0.35; // 35% of screen width
                      const buttonHeight =
                          70.0; // Even taller buttons for easier tapping
                      const spacing = 10.0;
                      const iconSize = 36.0; // Larger icons

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Forward button - centered
                          Center(
                            child: SizedBox(
                              width: buttonWidth,
                              height: buttonHeight,
                              child: ElevatedButton(
                                onPressed: () => _sendCommand('forward'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.zero,
                                  elevation: 3,
                                ),
                                child: Icon(Icons.arrow_upward, size: iconSize),
                              ),
                            ),
                          ),
                          SizedBox(height: spacing),

                          // Left and Right buttons in a row - evenly spaced
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left button
                              SizedBox(
                                width: buttonWidth,
                                height: buttonHeight,
                                child: ElevatedButton(
                                  onPressed: () => _sendCommand('left'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: EdgeInsets.zero,
                                    elevation: 3,
                                  ),
                                  child: Icon(Icons.arrow_back, size: iconSize),
                                ),
                              ),

                              // Right button
                              SizedBox(
                                width: buttonWidth,
                                height: buttonHeight,
                                child: ElevatedButton(
                                  onPressed: () => _sendCommand('right'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: EdgeInsets.zero,
                                    elevation: 3,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    size: iconSize,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing),

                          // Backward button - centered
                          Center(
                            child: SizedBox(
                              width: buttonWidth,
                              height: buttonHeight,
                              child: ElevatedButton(
                                onPressed: () => _sendCommand('backward'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.zero,
                                  elevation: 3,
                                ),
                                child: Icon(
                                  Icons.arrow_downward,
                                  size: iconSize,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),

            // Draggable front camera
            LayoutBuilder(
              builder: (context, constraints) {
                // Front camera with 3:4 aspect ratio
                final containerWidth = constraints.maxWidth - 32;
                final frontWidth = containerWidth * 0.3;
                final frontHeight = frontWidth * 4 / 3;

                return Positioned(
                  left: _frontCameraX,
                  top: _frontCameraY,
                  child: Draggable<String>(
                    data: 'frontCamera',
                    feedback: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: frontWidth,
                        height: frontHeight,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildFrontCameraView(),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: Container(
                        width: frontWidth,
                        height: frontHeight,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                    child: Container(
                      width: frontWidth,
                      height: frontHeight,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildFrontCameraView(),
                      ),
                    ),
                    onDragEnd: (details) {
                      setState(() {
                        // Calculate the position relative to the screen
                        _frontCameraX = details.offset.dx - 20;
                        _frontCameraY = details.offset.dy - 80;

                        // Get the available space dimensions
                        final screenWidth = MediaQuery.of(context).size.width;
                        final screenHeight = MediaQuery.of(context).size.height;
                        final safeAreaBottomPadding =
                            MediaQuery.of(context).padding.bottom;

                        // Boundary checks: keep camera within screen bounds
                        if (_frontCameraX < 0) _frontCameraX = 0;
                        if (_frontCameraX > screenWidth - frontWidth - 32) {
                          _frontCameraX = screenWidth - frontWidth - 32;
                        }
                        if (_frontCameraY < 0) _frontCameraY = 0;

                        // Allow going below buttons, but prevent going off screen bottom
                        final maxY =
                            screenHeight -
                            frontHeight -
                            safeAreaBottomPadding -
                            16;
                        if (_frontCameraY > maxY) {
                          _frontCameraY = maxY;
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontCameraView() {
    // Use actual camera if initialized
    if (_isCameraInitialized && _cameraController != null) {
      return AspectRatio(
        aspectRatio: _cameraController!.value.aspectRatio,
        child: CameraPreview(_cameraController!),
      );
    }
    // Fallback to video player if camera isn't available
    else if (_frontChewieController != null) {
      return Chewie(controller: _frontChewieController!);
    }
    // Loading state
    else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_front, size: 24, color: Colors.white54),
            SizedBox(height: 4),
            Text(
              'Loading...',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      );
    }
  }
}

class TrafficTab extends StatelessWidget {
  const TrafficTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traffic Management'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.traffic, size: 100, color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              'Traffic Management',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Monitor and control traffic signals',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traffic Map'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map, size: 100, color: Colors.green),
            const SizedBox(height: 20),
            Text(
              'Traffic Map',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'View real-time traffic conditions',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Navigate to settings
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile header
          const Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, size: 60, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'John Doe',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              'john.doe@example.com',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),

          const SizedBox(height: 32),

          // Profile menu items
          ProfileMenuItem(
            icon: Icons.person_outline,
            title: 'Personal Information',
            onTap: () {
              // TODO: Navigate to personal info
            },
          ),
          ProfileMenuItem(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            onTap: () {
              // TODO: Navigate to notifications
            },
          ),
          ProfileMenuItem(
            icon: Icons.security_outlined,
            title: 'Security',
            onTap: () {
              // TODO: Navigate to security
            },
          ),
          ProfileMenuItem(
            icon: Icons.history_outlined,
            title: 'Activity History',
            onTap: () {
              // TODO: Navigate to activity history
            },
          ),
          ProfileMenuItem(
            icon: Icons.help_outline,
            title: 'Help & Support',
            onTap: () {
              // TODO: Navigate to help
            },
          ),

          const SizedBox(height: 24),

          // Logout button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () async {
                await authService.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const ProfileMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
      ),
    );
  }
}
