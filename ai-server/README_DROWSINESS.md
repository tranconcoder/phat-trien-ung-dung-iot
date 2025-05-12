# Drowsiness Detection with ONNX Runtime

This directory contains tools for drowsiness detection using a DenseNet201 model.

## Setup Instructions

### Step 1: Convert the Keras model to ONNX format

The Python 3.13/3.14 environment can't run TensorFlow directly. You need to convert your Keras model to ONNX format using a different Python environment:

1. Create or use a Python 3.10 or 3.11 environment (TensorFlow compatible)
2. Install the required packages:
   ```
   pip install tensorflow==2.12.0 tf2onnx
   ```
3. Put your Keras model at `models/densenet201.keras`
4. Run the conversion script:
   ```
   python convert_model_standalone.py
   ```
5. This will create `models/densenet201.onnx` which can be used with ONNX Runtime

### Step 2: Run the drowsiness detector with ONNX Runtime

In your Python 3.13/3.14 environment, you can now use the ONNX model:

1. Make sure ONNX Runtime and MQTT are installed:

   ```
   pip install onnxruntime Pillow numpy paho-mqtt
   ```

2. Run the detection script in one of the following modes:

   **Process a single image:**

   ```
   python simple_drowsy_detector.py --image path/to/your/image.jpg --mqtt
   ```

   **Process all images in a directory (continuous mode):**

   ```
   python simple_drowsy_detector.py --dir path/to/images/folder --interval 1.5 --mqtt
   ```

   The `--mqtt` flag enables sending results to the MQTT broker.

## Command-Line Arguments

- `--model`: Path to the ONNX model file (default: models/densenet201.onnx)
- `--image`: Path to a single image to process
- `--dir`: Path to directory with images to process continuously
- `--interval`: Time interval (seconds) between processing images in directory mode (default: 1.0)
- `--mqtt`: Enable publishing results to MQTT

## MQTT Configuration

The detector publishes drowsiness detection results to MQTT topic `/drowsy` with the following format:

```json
{
  "result": "Drowsy",
  "class_index": 0,
  "probability": 0.95,
  "timestamp": 1623456789.123
}
```

## Connection Fallback

If the primary MQTT broker is unavailable, the script will try these alternatives in order:

1. Primary: `fd66ecb3.ala.asia-southeast1.emqxsl.com:8883` (TLS)
2. Fallback: `151.106.112.215:1883` (non-TLS)
3. Public: `broker.emqx.io:1883` (non-TLS)

## Troubleshooting

- If you see "Model not found" errors, ensure you've completed Step 1 to convert your Keras model to ONNX format
- Make sure the image files are valid JPG, PNG, or BMP formats
- Check the logs for detailed error messages
