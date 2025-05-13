import os
from ultralytics import YOLO
import shutil

# Create models directory if it doesn't exist
os.makedirs('models', exist_ok=True)

print("Downloading YOLOv8n model...")
model = YOLO("yolov8n.pt")
print(f"Model loaded successfully: {model}")

# Save the model to the models directory
model_path = os.path.join('models', 'best.pt')
print(f"Saving model to {model_path}...")

# Create a copy of the original yolov8n.pt file
shutil.copy(model.ckpt_path, model_path)

print(f"Model saved to {model_path}")
print(f"Model size: {os.path.getsize(model_path)} bytes") 