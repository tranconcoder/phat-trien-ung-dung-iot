import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class DriverCameraTab extends StatefulWidget {
  const DriverCameraTab({Key? key}) : super(key: key);

  @override
  State<DriverCameraTab> createState() => _DriverCameraTabState();
}

class _DriverCameraTabState extends State<DriverCameraTab>
    with WidgetsBindingObserver {
  // Camera controller
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // WebSocket for sending camera frames
  WebSocketChannel? _webSocketChannel;
  bool _isConnected = false;
  Timer? _heartbeatTimer; // Add heartbeat timer

  // Socket.IO for receiving drowsiness results
  late IO.Socket _socket;
  bool _isSocketConnected = false;

  // Drowsiness detection state
  String _drowsinessResult = "Waiting for detection...";
  double _drowsinessProbability = 0.0;
  bool _isDrowsy = false;
  DateTime _lastUpdate = DateTime.now();

  // Alert sound player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAlertPlaying = false;
  bool _alertEnabled = true;
  Timer? _alertCooldownTimer;

  // Frame capture settings
  Timer? _captureTimer;
  bool _isCapturing = false;
  bool _processingFrame = false;
  int _frameCount = 0;
  int _frameInterval = 200; // ms between frames
  int _frameThrottle = 3; // Only send 1 of every X frames

  // Server connection
  String _serverIp = "";

  // Add at the class level with other state variables
  String _cameraErrorMessage = '';
  bool _hasCameraError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadServerIp().then((_) {
      _initializeCamera();
      _initializeSocketIO();
    });
    _initializeAudioPlayer();
  }

  // Initialize audio player and prepare alert sound
  Future<void> _initializeAudioPlayer() async {
    try {
      // Set audio session configuration for alerts
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      debugPrint('Audio player initialized');
    } catch (e) {
      debugPrint('Error initializing audio player: $e');
    }
  }

  // Play alert sound when drowsy
  Future<void> _playAlertSound() async {
    if (!_alertEnabled || _isAlertPlaying) return;

    try {
      setState(() {
        _isAlertPlaying = true;
      });

      // Vibrate the phone
      HapticFeedback.heavyImpact();

      // Play alert sound using the correct method
      await _audioPlayer.play(AssetSource('sounds/wake_up_alert.mp3'));

      // Cancel any existing cooldown timer
      _alertCooldownTimer?.cancel();

      // Set a timer to stop the alert after 5 seconds
      _alertCooldownTimer = Timer(const Duration(seconds: 5), () {
        _stopAlertSound();

        // Set a cooldown period before allowing alerts again
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) {
            setState(() {
              _alertEnabled = true;
            });
          }
        });
      });

      debugPrint('Started playing alert sound');
    } catch (e) {
      debugPrint('Error playing alert sound: $e');
      setState(() {
        _isAlertPlaying = false;
      });
    }
  }

  // Stop alert sound
  Future<void> _stopAlertSound() async {
    if (!_isAlertPlaying) return;

    try {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _isAlertPlaying = false;
          _alertEnabled = false; // Prevent immediate re-triggering
        });
      }
      debugPrint('Stopped playing alert sound');
    } catch (e) {
      debugPrint('Error stopping alert sound: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCapturing();
    _cameraController?.dispose();
    _webSocketChannel?.sink.close();
    _heartbeatTimer?.cancel(); // Cancel heartbeat timer
    _alertCooldownTimer?.cancel();
    _audioPlayer.dispose();
    if (_isSocketConnected) {
      _socket.disconnect();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app state changes
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopCapturing();
      _stopAlertSound();
    } else if (state == AppLifecycleState.resumed) {
      if (_isCapturing) {
        _startCapturing();
      }
    }
  }

  // Load server IP from preferences
  Future<void> _loadServerIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('websocket_ip_address');
      if (savedIp != null && savedIp.isNotEmpty) {
        setState(() {
          _serverIp = savedIp;
        });
      } else {
        // Default to IP from app config
        setState(() {
          _serverIp = AppConfig.SOCKETIO_URL
              .replaceAll('http://', '')
              .replaceAll(':4001', '');
        });
      }
      debugPrint('Using server IP: $_serverIp');
    } catch (e) {
      debugPrint('Error loading server IP: $e');
      // Use fallback
      setState(() {
        _serverIp = "192.168.1.10"; // Default fallback
      });
    }
  }

  // Initialize Socket.IO connection for receiving drowsiness results
  void _initializeSocketIO() {
    try {
      final socketUrl = 'http://$_serverIp:4001';
      debugPrint('Connecting to Socket.IO: $socketUrl');

      _socket = IO.io(socketUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnectionAttempts': 5, // Limit reconnection attempts
        'reconnectionDelay': 2000, // Wait 2 seconds between attempts
        'reconnectionDelayMax': 10000, // Max delay of 10 seconds
        'timeout': 10000, // Connection timeout of 10 seconds
        'pingTimeout': 5000, // Server must respond to pings within 5 seconds
        'pingInterval': 3000, // Send ping every 3 seconds
      });

      _socket.onConnect((_) {
        debugPrint('Socket.IO connected');
        setState(() {
          _isSocketConnected = true;
        });
      });

      _socket.onDisconnect((_) {
        debugPrint('Socket.IO disconnected');
        setState(() {
          _isSocketConnected = false;
        });
      });

      _socket.onConnectError((error) {
        debugPrint('Socket.IO connect error: $error');
        setState(() {
          _isSocketConnected = false;
        });
      });

      // Use onError instead of onConnectTimeout which isn't available
      _socket.onError((error) {
        debugPrint('Socket.IO error: $error');
        setState(() {
          _isSocketConnected = false;
        });
      });

      // Listen for drowsiness detection results
      _socket.on('drowsy', (data) {
        debugPrint('Received drowsiness data: $data');
        if (data != null && data is Map) {
          setState(() {
            _drowsinessResult = data['result'] ?? "Unknown";
            _drowsinessProbability = data['probability'] ?? 0.0;
            _isDrowsy = _drowsinessResult == 'Drowsy';
            _lastUpdate = DateTime.now();

            // Check if drowsiness probability is above threshold (95%)
            if (_isDrowsy && _drowsinessProbability > 0.95) {
              _playAlertSound();
            } else if (_isAlertPlaying &&
                (!_isDrowsy || _drowsinessProbability <= 0.90)) {
              // Stop alert if no longer drowsy or probability drops below 90%
              _stopAlertSound();
            }
          });
        }
      });

      _socket.connect();
    } catch (e) {
      debugPrint('Error connecting to Socket.IO: $e');
    }
  }

  // Initialize the camera
  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _hasCameraError = false;
        _cameraErrorMessage = '';
      });

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _hasCameraError = true;
          _cameraErrorMessage = 'No cameras found on this device.';
        });
        return;
      }

      // Find front camera
      CameraDescription? frontCamera;
      try {
        frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
        );
      } catch (e) {
        // If no front camera, use the first available
        debugPrint('No front camera found, using first available camera');
        frontCamera = cameras.first;
      }

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Camera initialization timed out');
        },
      );

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // Auto-start capturing after initialization
        _startCapturing();
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');

      if (mounted) {
        setState(() {
          _hasCameraError = true;
          _cameraErrorMessage = 'Failed to initialize camera: $e';
          _isCameraInitialized = false;
        });

        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeCamera,
            ),
          ),
        );
      }
    }
  }

  // Connect to WebSocket for sending camera frames
  void _connectWebSocket() {
    try {
      // Cancel any existing heartbeat timer
      _heartbeatTimer?.cancel();

      final wsUrl = 'ws://$_serverIp:8887/drivercam';
      debugPrint('Connecting to WebSocket: $wsUrl');

      _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Listen for connection closed events
      _webSocketChannel!.stream.listen(
        (dynamic message) {
          // Handle incoming messages (if any)
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          setState(() {
            _isConnected = false;
          });
          _heartbeatTimer?.cancel();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          setState(() {
            _isConnected = false;
          });
          _heartbeatTimer?.cancel();

          // Try to reconnect if we're still capturing
          if (mounted && _isCapturing) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _isCapturing) {
                _connectWebSocket();
              }
            });
          }
        },
      );

      setState(() {
        _isConnected = true;
      });

      // Start heartbeat timer to detect server disconnection
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _checkConnection();
      });
    } catch (e) {
      debugPrint('Error connecting to WebSocket: $e');
      setState(() {
        _isConnected = false;
      });

      // Retry connection after delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isCapturing) {
          _connectWebSocket();
        }
      });
    }
  }

  // Check if connection is still active
  void _checkConnection() {
    if (_webSocketChannel == null || !_isConnected) return;

    try {
      // Try to send a ping message to check connection
      _webSocketChannel!.sink.add(Uint8List(0)); // Empty ping message
    } catch (e) {
      debugPrint('Connection check failed: $e');
      setState(() {
        _isConnected = false;
      });

      // Reconnect if needed
      if (mounted && _isCapturing) {
        _connectWebSocket();
      }
    }
  }

  // Start capturing and sending camera frames
  void _startCapturing() {
    if (!_isCameraInitialized || _isCapturing) return;

    // Connect to WebSocket if needed
    if (!_isConnected) {
      _connectWebSocket();
    }

    setState(() {
      _isCapturing = true;
    });

    // Start periodic frame capture
    _captureTimer = Timer.periodic(Duration(milliseconds: _frameInterval), (_) {
      _captureAndSendFrame();
    });

    debugPrint('Started camera capture');
  }

  // Stop capturing frames
  void _stopCapturing() {
    _captureTimer?.cancel();
    _captureTimer = null;

    setState(() {
      _isCapturing = false;
    });

    // Stop alert sound when stopping capture
    _stopAlertSound();

    debugPrint('Stopped camera capture');
  }

  // Capture and send a single frame
  Future<void> _captureAndSendFrame() async {
    if (!mounted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isConnected ||
        _processingFrame) {
      return;
    }

    // Throttle frames if needed
    _frameCount++;
    if (_frameCount % _frameThrottle != 0) {
      return;
    }

    try {
      _processingFrame = true;

      // Check camera availability
      if (!_cameraController!.value.isInitialized ||
          _cameraController!.value.isTakingPicture) {
        _processingFrame = false;
        return;
      }

      // Capture image
      XFile? image;
      try {
        image = await _cameraController!.takePicture();
      } catch (e) {
        debugPrint('Error taking picture: $e');
        _processingFrame = false;
        return;
      }

      // Read image bytes
      Uint8List imageBytes;
      try {
        imageBytes = await image.readAsBytes();
      } catch (e) {
        debugPrint('Error reading image bytes: $e');
        _processingFrame = false;
        return;
      }

      // Send via WebSocket
      if (_webSocketChannel != null && _isConnected) {
        try {
          _webSocketChannel!.sink.add(imageBytes);
          debugPrint('Sent frame: ${imageBytes.length} bytes');
        } catch (e) {
          debugPrint('Error sending frame: $e');
          // Mark as disconnected
          setState(() {
            _isConnected = false;
          });
          // Reconnect on error
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _isCapturing) {
              _connectWebSocket();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error in capture process: $e');
    } finally {
      _processingFrame = false;
    }
  }

  // Add this method to show the server IP configuration dialog
  void _showServerIpDialog() {
    final TextEditingController ipController =
        TextEditingController(text: _serverIp);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Server IP Address',
                hintText: 'e.g., 192.168.1.10',
                helperText: 'IP address of the server running main.py',
              ),
              keyboardType: TextInputType.text,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newIp = ipController.text.trim();
              if (newIp.isNotEmpty) {
                try {
                  // Save to SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('websocket_ip_address', newIp);

                  // Update state
                  setState(() {
                    _serverIp = newIp;
                  });

                  // Disconnect existing connections
                  _webSocketChannel?.sink.close();
                  _webSocketChannel = null;
                  _isConnected = false;

                  if (_isSocketConnected) {
                    _socket.disconnect();
                  }

                  // Reconnect with new IP
                  _initializeSocketIO();
                  if (_isCapturing) {
                    _connectWebSocket();
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Server IP updated to $_serverIp')),
                  );
                } catch (e) {
                  debugPrint('Error saving IP: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving IP: $e')),
                  );
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Drowsiness Detection'),
        actions: [
          // Alert toggle button
          IconButton(
            icon: Icon(
              _alertEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              color: _alertEnabled ? Colors.amber : Colors.grey,
            ),
            tooltip: _alertEnabled ? 'Disable Alerts' : 'Enable Alerts',
            onPressed: () {
              setState(() {
                _alertEnabled = !_alertEnabled;
                if (!_alertEnabled && _isAlertPlaying) {
                  _stopAlertSound();
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(_alertEnabled
                        ? 'Drowsiness alerts enabled'
                        : 'Drowsiness alerts disabled')),
              );
            },
          ),
          // Server settings button
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Server Settings',
            onPressed: _showServerIpDialog,
          ),
          // Connection status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.check_circle : Icons.error_outline,
                  size: 14,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Server info display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blueGrey.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.computer, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  'Server: $_serverIp',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _showServerIpDialog,
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          // Camera preview
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black,
              child: _isCameraInitialized
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Transform.scale(
                        scale: 1.0,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio:
                                1 / _cameraController!.value.aspectRatio,
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: _hasCameraError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24),
                                  child: Text(
                                    _cameraErrorMessage,
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _initializeCamera,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry Camera'),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Initializing camera...',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.7)),
                                ),
                              ],
                            ),
                    ),
            ),
          ),

          // Drowsiness detection result
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _isDrowsy
                ? (_drowsinessProbability > 0.95
                    ? Colors.red.shade900
                    : Colors.red.shade800)
                : Colors.green.shade800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _drowsinessResult,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isAlertPlaying) const SizedBox(width: 12),
                    if (_isAlertPlaying)
                      const Icon(
                        Icons.notifications_active,
                        color: Colors.amber,
                        size: 24,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Confidence: ${(_drowsinessProbability * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _drowsinessProbability,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _isDrowsy
                        ? (_drowsinessProbability > 0.95
                            ? Colors.red.shade100
                            : Colors.red.shade300)
                        : Colors.green.shade300,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Last update: ${_timeSinceUpdate()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isCapturing ? _stopCapturing : _startCapturing,
                  icon: Icon(_isCapturing ? Icons.stop : Icons.play_arrow),
                  label: Text(_isCapturing ? 'Stop' : 'Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCapturing ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // Reset connection
                    _webSocketChannel?.sink.close();
                    _webSocketChannel = null;
                    _isConnected = false;

                    // Reconnect
                    if (_isCapturing) {
                      _connectWebSocket();
                    }

                    // Reconnect Socket.IO
                    _socket.disconnect();
                    _socket.connect();

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reconnecting...')),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconnect'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Format time since last update
  String _timeSinceUpdate() {
    final now = DateTime.now();
    final difference = now.difference(_lastUpdate);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} seconds ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return '${difference.inHours} hours ago';
    }
  }
}
