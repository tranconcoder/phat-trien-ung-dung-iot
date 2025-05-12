# This script converts a Keras model to ONNX format
# Install required packages: pip install tf2onnx tensorflow==2.12.0

import tf2onnx
import tensorflow as tf
import sys
import os

def convert_keras_to_onnx(keras_model_path, onnx_model_path):
    # Load the Keras model
    model = tf.keras.models.load_model(keras_model_path)
    
    # Convert the model to ONNX format
    model_proto, _ = tf2onnx.convert.from_keras(model)
    
    # Save the ONNX model
    with open(onnx_model_path, "wb") as f:
        f.write(model_proto.SerializeToString())
    
    print(f"Model converted and saved to {onnx_model_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python convert_model.py <keras_model_path> <onnx_model_path>")
        sys.exit(1)
    
    keras_model_path = sys.argv[1]
    onnx_model_path = sys.argv[2]
    
    if not os.path.exists(keras_model_path):
        print(f"Error: Keras model file {keras_model_path} does not exist")
        sys.exit(1)
    
    convert_keras_to_onnx(keras_model_path, onnx_model_path) 