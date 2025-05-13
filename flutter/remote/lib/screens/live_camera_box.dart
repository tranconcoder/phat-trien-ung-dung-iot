import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import '../config/app_config.dart';

class LiveCameraBox extends StatefulWidget {
  const LiveCameraBox({Key? key}) : super(key: key);

  @override
  State<LiveCameraBox> createState() => _LiveCameraBoxState();
}

class _LiveCameraBoxState extends State<LiveCameraBox>
    with SingleTickerProviderStateMixin {
  IOWebSocketChannel? _webSocketChannel;
  bool _isConnected = false;
  Uint8List? _imageData;
  String _status = 'Chưa kết nối';
  double _windowSize = 180.0; // Smaller initial floating window size
  bool _isDragging = false;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _connectToWebSocket();

    // Setup pulsing animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _disconnectWebSocket();
    _animationController.dispose();
    super.dispose();
  }

  void _connectToWebSocket() {
    try {
      // Create WebSocket connection using the predefined WEBSOCKET_URL
      _webSocketChannel = IOWebSocketChannel.connect(
        Uri.parse('${AppConfig.WEBSOCKET_URL}/frontcam'),
        pingInterval: const Duration(seconds: 5),
      );

      setState(() {
        _status = 'Đang kết nối...';
      });

      _webSocketChannel!.stream.listen(
        (dynamic message) {
          // Handle binary data (image)
          if (message is List<int>) {
            setState(() {
              _imageData = Uint8List.fromList(message);
              _isConnected = true;
              _status = 'Đã kết nối';
            });
          }
        },
        onError: (error) {
          setState(() {
            _isConnected = false;
            _status = 'Lỗi kết nối: $error';
          });
        },
        onDone: () {
          setState(() {
            _isConnected = false;
            _status = 'Kết nối đã đóng';
          });
        },
      );
    } catch (e) {
      setState(() {
        _isConnected = false;
        _status = 'Lỗi: $e';
      });
    }
  }

  void _disconnectWebSocket() {
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _status = 'Đã ngắt kết nối';
      });
    }
  }

  void _toggleConnection() {
    if (_isConnected) {
      _disconnectWebSocket();
    } else {
      _connectToWebSocket();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 80,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _isConnected ? 1.0 : _pulseAnimation.value,
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
                final RenderBox renderBox =
                    context.findRenderObject() as RenderBox;
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
                      color: _isConnected ? Colors.green : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: _isConnected
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
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                            Row(
                              children: [
                                // Resize handle
                                GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      _windowSize =
                                          (_windowSize + details.delta.dx)
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
                                    _disconnectWebSocket();
                                    LiveCameraBoxOverlay.hide();
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
                          child: _imageData != null
                              ? Image.memory(
                                  _imageData!,
                                  fit: BoxFit.cover,
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _isConnected
                                          ? const CircularProgressIndicator()
                                          : const Icon(
                                              Icons.videocam_off,
                                              color: Colors.white,
                                              size: 40,
                                            ),
                                      const SizedBox(height: 8),
                                      Text(_status,
                                          style: const TextStyle(
                                              color: Colors.white),
                                          textAlign: TextAlign.center),
                                    ],
                                  ),
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
                                _isConnected ? Icons.pause : Icons.play_arrow,
                                color: _isConnected ? Colors.red : Colors.green,
                              ),
                              iconSize: 20,
                              onPressed: _toggleConnection,
                              tooltip:
                                  _isConnected ? 'Ngắt kết nối' : 'Kết nối',
                            ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8.0),
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
        },
      ),
    );
  }
}

// Overlay entry point for floating window
class LiveCameraBoxOverlay {
  static OverlayEntry? _overlayEntry;

  static void show(BuildContext context) {
    if (_overlayEntry != null) {
      return; // Already showing
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => const LiveCameraBox(),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static void toggle(BuildContext context) {
    if (_overlayEntry != null) {
      hide();
    } else {
      show(context);
    }
  }
}
