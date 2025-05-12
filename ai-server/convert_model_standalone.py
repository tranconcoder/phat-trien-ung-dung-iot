# This standalone script converts a Keras model to ONNX format
# Run this with Python 3.10 or 3.11 which supports TensorFlow
# pip install tensorflow==2.12.0 tf2onnx

import sys
import os
import tensorflow as tf
from tensorflow import keras
import tf2onnx

def convert_keras_to_onnx(keras_model_path, onnx_model_path):
    # Load the Keras model
    print(f"Loading Keras model from: {keras_model_path}")
    model = keras.models.load_model(keras_model_path)
    print("Model loaded successfully")
    
    # Convert the model to ONNX format
    print(f"Converting model to ONNX format")
    model_proto, _ = tf2onnx.convert.from_keras(model)
    
    # Save the ONNX model
    print(f"Saving ONNX model to: {onnx_model_path}")
    with open(onnx_model_path, "wb") as f:
        f.write(model_proto.SerializeToString())
    
    print(f"Model converted and saved successfully")

if __name__ == "__main__":
    # Define the paths
    keras_model_path = "models/densenet201.keras"
    onnx_model_path = "models/densenet201.onnx"
    
    # Get full paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    keras_model_full_path = os.path.join(script_dir, keras_model_path)
    onnx_model_full_path = os.path.join(script_dir, onnx_model_path)
    
    # Check if Keras model exists
    if not os.path.exists(keras_model_full_path):
        print(f"Error: Keras model file {keras_model_full_path} does not exist")
        sys.exit(1)
    
    # Make sure the output directory exists
    os.makedirs(os.path.dirname(onnx_model_full_path), exist_ok=True)
    
    # Convert the model
    convert_keras_to_onnx(keras_model_full_path, onnx_model_full_path)
    
    print(f"Run your ONNX model with: python main.py") 