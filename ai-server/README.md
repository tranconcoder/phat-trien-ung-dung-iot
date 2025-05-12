# AI Server with Drowsiness Detection

This server processes driver camera images to detect drowsiness and sends the results via MQTT.

## Prerequisites

- Python 3.8+ (Python 3.13 supported)
- Required packages: `onnxruntime`, `numpy`, `Pillow`, `paho-mqtt`, `socketio`, `eventlet`, `matplotlib`

## Getting Started

### 1. Install Dependencies

```bash
pip install onnxruntime Pillow numpy paho-mqtt python-socketio eventlet matplotlib
```

### 2. Convert the Keras Model to ONNX (if needed)

If you already have a Keras model (`densenet201.keras`), you need to convert it to ONNX format:

```bash
# Install TensorFlow and TF2ONNX in a Python environment that supports TensorFlow
# (Note: Python 3.11 or earlier is recommended for TensorFlow)
pip install tensorflow==2.12.0 tf2onnx

# Run the conversion script
python convert_model.py models/densenet201.keras models/densenet201.onnx
```

### 3. Test the Model

You can test the drowsiness detection model on a single image:

```bash
python test_drowsiness.py path/to/test/image.jpg
```

### 4. Run the Server

```bash
python main.py
```

This will start:

- A Socket.IO server on port 4001
- A WebSocket server on port 8887

## How It Works

1. The server receives images from two sources:

   - ESP32 camera via WebSocket (`/frontcam`)
   - Driver camera via WebSocket (`/drivercam`)

2. When driver camera images are received, the server:

   - Processes the image using the drowsiness detection model
   - Publishes the results to MQTT topic `/drowsy`
   - Forwards the image to connected Socket.IO clients

3. MQTT Messages Format:
   ```json
   {
     "result": "Drowsy",
     "class_index": 0,
     "probability": 0.95,
     "timestamp": 1623456789.123
   }
   ```

## MQTT Configuration

The server attempts to connect to multiple MQTT brokers in this order:

1. Primary: `fd66ecb3.ala.asia-southeast1.emqxsl.com:8883` (TLS)
2. Fallback: `151.106.112.215:1883` (non-TLS)
3. Public: `broker.emqx.io:1883` (non-TLS)

## Troubleshooting

- If you encounter model loading errors, ensure your model is in ONNX format
- For TLS connection issues, you may need to provide custom certificates
- Monitor the log output for detailed error messages

## License

This project is licensed under the MIT License.
