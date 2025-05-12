import onnxruntime as ort
import numpy as np
from PIL import Image
import os
import argparse
import matplotlib.pyplot as plt

def detect_drowsiness(image_path, model_path="models/densenet201.onnx"):
    # Check if model exists
    if not os.path.exists(model_path):
        print(f"Error: Model file {model_path} does not exist")
        return None
        
    # Load ONNX model
    try:
        model = ort.InferenceSession(model_path)
        print(f"Model loaded successfully from {model_path}")
    except Exception as e:
        print(f"Error loading model: {e}")
        return None
        
    # Load and preprocess image
    try:
        image = Image.open(image_path)
        image_resized = image.resize((224, 224))
        image_array = np.array(image_resized).astype(np.float32)
        image_array = image_array / 255.0
        image_array = np.expand_dims(image_array, axis=0)
        
        # Get input and output names
        input_name = model.get_inputs()[0].name
        output_name = model.get_outputs()[0].name
        
        # Make prediction
        predictions = model.run([output_name], {input_name: image_array})[0]
        
        # Get class with highest probability
        class_index = np.argmax(predictions[0])
        probability = float(predictions[0][class_index])
        
        # Determine result
        result = "Drowsy" if class_index == 0 else "Non-Drowsy"
        
        # Display results
        print(f"Drowsiness detection result: {result} ({probability * 100:.2f}%)")
        print("Probability breakdown:")
        for i, prob in enumerate(predictions[0]):
            status = "Drowsy" if i == 0 else "Non-Drowsy"
            print(f"  Class {i} ({status}): {prob * 100:.2f}%")
            
        # Show image with result
        plt.figure(figsize=(6, 6))
        plt.imshow(image_resized)
        plt.title(f"Result: {result} ({probability * 100:.2f}%)")
        plt.axis('off')
        plt.show()
        
        return {
            "result": result,
            "class_index": int(class_index),
            "probability": probability
        }
    except Exception as e:
        print(f"Error processing image: {e}")
        return None

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test drowsiness detection on a single image")
    parser.add_argument("image_path", help="Path to the image file")
    parser.add_argument("--model", default="models/densenet201.onnx", help="Path to the ONNX model file")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.image_path):
        print(f"Error: Image file {args.image_path} does not exist")
        exit(1)
        
    result = detect_drowsiness(args.image_path, args.model)
    if result:
        print("Detection successful!") 