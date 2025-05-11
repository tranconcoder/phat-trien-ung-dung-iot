# Socket.IO Image Streaming Server

This is a Python-based Socket.IO server that streams camera images to connected clients and receives control commands.

## Features

- Streams real-time camera images to Flutter app
- Handles vehicle control commands from the app
- Provides test image generation when no camera is available
- Supports room-based connection management
- Displays received commands on test images

## Setup

### Prerequisites

- Python 3.7 or higher
- pip (Python package manager)
- A webcam (optional - test images will be used if no camera is found)

### Installation

1. Clone this repository
2. Install the required packages:

```bash
pip install -r requirements.txt
```

### Running the Server

To start the server:

```bash
python server.py
```

To use test images instead of trying to access a camera:

```bash
USE_TEST_IMAGE=true python server.py
```

By default, the server runs on port 5000. You can change this by setting the PORT environment variable:

```bash
PORT=8080 python server.py
```

## Socket.IO Events

### Server Events (that clients can listen to)

- `image`: Emits base64-encoded image data
- `command_received`: Confirmation that a command was received
- `message`: Server messages

### Client Events (that clients can emit)

- `joinRoom`: Join a room (e.g., 'camera_feed')
- `control`: Send a control command to the server

## Integration with Flutter App

1. Make sure your Flutter app has the Socket.IO client package installed
2. Configure your app to connect to this server
3. Join the 'camera_feed' room to receive images
4. Send control commands as JSON with command and timestamp fields

Example socket.io connection in Flutter:

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

// Initialize Socket.IO
socket = IO.io('http://your_server_ip:5000', <String, dynamic>{
  'transports': ['websocket'],
  'autoConnect': true,
});

// Connect and handle events
socket.onConnect((_) {
  print('Connected to server');
  socket.emit('joinRoom', 'camera_feed');
});

socket.on('image', (data) {
  // Handle image data (base64 string)
  setState(() {
    _mainImageBytes = base64Decode(data);
  });
});

// Send control command
void sendCommand(String direction) {
  final payload = {
    'command': direction,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  socket.emit('control', jsonEncode(payload));
}
```
