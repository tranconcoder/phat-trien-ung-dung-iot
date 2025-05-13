import os
import logging
from ultralytics import YOLO

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Model paths
YOLO_MODEL_PATH = 'models/best.pt'
FULL_YOLO_MODEL_PATH = os.path.join('C:', os.sep, 'Users', 'tranv', 'Workspace', 'pt_iot', 'ai-server', 'models', 'best.pt')

print(f"Checking model at relative path: {YOLO_MODEL_PATH}")
print(f"File exists: {os.path.exists(YOLO_MODEL_PATH)}")

print(f"Checking model at absolute path: {FULL_YOLO_MODEL_PATH}")
print(f"File exists: {os.path.exists(FULL_YOLO_MODEL_PATH)}")

# Try to load the model
try:
    if os.path.exists(FULL_YOLO_MODEL_PATH):
        print("Loading model from absolute path...")
        model = YOLO(FULL_YOLO_MODEL_PATH)
        print("Model loaded successfully")
    elif os.path.exists(YOLO_MODEL_PATH):
        print("Loading model from relative path...")
        model = YOLO(YOLO_MODEL_PATH)
        print("Model loaded successfully")
    else:
        print("Model not found at either path")
except Exception as e:
    print(f"Error loading model: {e}") 