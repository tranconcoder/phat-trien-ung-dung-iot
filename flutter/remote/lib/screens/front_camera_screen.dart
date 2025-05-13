import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import '../config/app_config.dart';

class FrontCameraScreen extends StatefulWidget {
  const FrontCameraScreen({Key? key}) : super(key: key);

  @override
  State<FrontCameraScreen> createState() => _FrontCameraScreenState();
}

class _FrontCameraScreenState extends State<FrontCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isStreaming = false;
  IOWebSocketChannel? _webSocketChannel;
  Timer? _streamTimer;
  String _status = 'Khởi động camera...';
  int _framesSent = 0;
  double _windowSize = 240.0; // Initial floating window size
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreaming();
    _controller?.dispose();
    _streamTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed - handle camera access when app is inactive
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopStreaming();
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _status = 'Không tìm thấy camera';
        });
        return;
      }

      // Find front camera
      CameraDescription? frontCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      // If no front camera is found, use the first camera
      final cameraToUse = frontCamera ?? _cameras!.first;

      _controller = CameraController(
        cameraToUse,
        ResolutionPreset.medium, // Medium quality to balance performance
        enableAudio: false, // Audio not needed for streaming
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _status = 'Camera sẵn sàng';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Lỗi khởi tạo camera: $e';
      });
    }
  }

  Future<void> _toggleStreaming() async {
    if (_isStreaming) {
      _stopStreaming();
    } else {
      _startStreaming();
    }
  }

  Future<void> _startStreaming() async {
    if (!_isInitialized ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      setState(() {
        _status = 'Camera chưa được khởi tạo';
      });
      return;
    }

    try {
      // Create WebSocket connection
      final wsUrl =
          'ws://${AppConfig.SERVER_URL.replaceAll(RegExp(r'https?://'), '')}/frontcam';
      _webSocketChannel = IOWebSocketChannel.connect(wsUrl);

      setState(() {
        _isStreaming = true;
        _status = 'Đang kết nối WebSocket...';
        _framesSent = 0;
      });

      // Stream images periodically
      _streamTimer =
          Timer.periodic(const Duration(milliseconds: 200), (_) async {
        if (_isStreaming &&
            _controller != null &&
            _controller!.value.isInitialized) {
          try {
            final XFile imageFile = await _controller!.takePicture();
            final bytes = await imageFile.readAsBytes();

            // Send image through WebSocket
            _webSocketChannel?.sink.add(bytes);

            setState(() {
              _framesSent++;
              _status = 'Đang phát: $_framesSent frames đã gửi';
            });
          } catch (e) {
            setState(() {
              _status = 'Lỗi chụp/gửi ảnh: $e';
            });
          }
        }
      });
    } catch (e) {
      setState(() {
        _isStreaming = false;
        _status = 'Lỗi kết nối: $e';
      });
    }
  }

  void _stopStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;

    _webSocketChannel?.sink.close();
    _webSocketChannel = null;

    if (mounted) {
      setState(() {
        _isStreaming = false;
        _status = 'Đã dừng phát';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 100,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() {
            _isDragging = true;
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
          });
        },
        onPanUpdate: (details) {
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          final position = renderBox.localToGlobal(Offset.zero);

          // Get the current overlay context to determine screen boundaries
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox;

          // Calculate new position
          final newX = position.dx + details.delta.dx;
          final newY = position.dy + details.delta.dy;

          // Ensure the window stays within screen bounds
          if (newX >= 0 &&
              newX + _windowSize <= overlay.size.width &&
              newY >= 0 &&
              newY + _windowSize <= overlay.size.height) {
            setState(() {});
          }
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: _windowSize,
            height: _windowSize,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isStreaming ? Colors.green : Colors.grey,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isStreaming
                        ? Colors.green.shade800
                        : Colors.grey.shade800,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: Text(
                          'Camera Trước',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Row(
                        children: [
                          // Resize handle
                          GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _windowSize = (_windowSize + details.delta.dx)
                                    .clamp(160.0, 400.0);
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.zoom_out_map,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                          // Close button
                          GestureDetector(
                            onTap: () {
                              _stopStreaming();
                              Navigator.of(context).pop();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Camera preview
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    child: _isInitialized && _controller != null
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: CameraPreview(_controller!),
                          )
                        : Center(
                            child: _cameras == null
                                ? const CircularProgressIndicator()
                                : Text(_status,
                                    style:
                                        const TextStyle(color: Colors.white)),
                          ),
                  ),
                ),

                // Controls
                Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isStreaming ? Icons.stop : Icons.play_arrow,
                          color: _isStreaming ? Colors.red : Colors.green,
                        ),
                        iconSize: 20,
                        onPressed: _toggleStreaming,
                        tooltip: _isStreaming ? 'Dừng phát' : 'Bắt đầu phát',
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            _status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Overlay entry point for floating window
class FrontCameraOverlay {
  static OverlayEntry? _overlayEntry;

  static void show(BuildContext context) {
    if (_overlayEntry != null) {
      return; // Already showing
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => const FrontCameraScreen(),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
