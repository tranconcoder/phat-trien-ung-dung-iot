import os
import sys
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# YOLOv8 model path
YOLO_MODEL_PATH = 'models/best.pt'
FULL_YOLO_MODEL_PATH = os.path.join('C:', os.sep, 'Users', 'tranv', 'Workspace', 'pt_iot', 'ai-server', 'models', 'best.pt')

print("=" * 50)
print("MODEL LOADING TEST")
print("=" * 50)
print(f"Python version: {sys.version}")
print(f"Current working directory: {os.getcwd()}")
print(f"Absolute path to model: {os.path.abspath(FULL_YOLO_MODEL_PATH)}")

# Check if model exists
for path in [FULL_YOLO_MODEL_PATH, YOLO_MODEL_PATH]:
    print(f"\nChecking path: {path}")
    exists = os.path.exists(path)
    print(f"File exists: {exists}")
    if exists:
        size = os.path.getsize(path)
        print(f"File size: {size:,} bytes ({size/1024/1024:.2f} MB)")

# Try to load model
print("\nAttempting to load model...")
try:
    # First try importing the module
    try:
        from ultralytics import YOLO
        print("Successfully imported ultralytics YOLO")
    except ImportError as ie:
        print(f"ERROR: Failed to import ultralytics: {ie}")
        print("Please install using: pip install ultralytics")
        sys.exit(1)
    
    # Try loading the model
    for path in [FULL_YOLO_MODEL_PATH, YOLO_MODEL_PATH]:
        if os.path.exists(path):
            print(f"Loading model from: {path}")
            try:
                model = YOLO(path)
                print(f"SUCCESS: Model loaded from {path}")
                print(f"Model info: {model}")
                sys.exit(0)
            except Exception as e:
                print(f"ERROR: Failed to load model from {path}: {e}")
    
    print("ERROR: Could not load model from any path")
except Exception as e:
    print(f"Unexpected error: {e}") 