import socketio
import eventlet
from eventlet import websocket
import logging
import io
import numpy as np
import os
import json
import time
from PIL import Image
import paho.mqtt.client as mqtt
import sys
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import cv2

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Import TensorFlow and Keras
try:
    import tensorflow as tf
    from tensorflow.keras.models import load_model
    logger.info("TensorFlow imported successfully")
    have_tensorflow = True
except ImportError:
    logger.error("TensorFlow import failed - please install tensorflow")
    print("WARNING: TensorFlow import failed - drowsiness detection will be disabled")
    have_tensorflow = False

# Import ultralytics YOLOv8
try:
    from ultralytics import YOLO
    logger.info("YOLOv8 imported successfully")
    have_yolo = True
except ImportError:
    logger.error("YOLOv8 import failed - please install ultralytics")
    print("WARNING: YOLOv8 import failed - traffic sign detection will be disabled")
    have_yolo = False

# Socket.IO setup
sio = socketio.Server(cors_allowed_origins='*', binary=True)
app = socketio.WSGIApp(sio)

# Global variables
clients_connected = 0
last_esp32_image = None
last_driver_image = None

# MQTT Configuration from Flutter app config
MQTT_BROKER = 'fd66ecb3.ala.asia-southeast1.emqxsl.com'
MQTT_PORT = 8883
MQTT_USE_TLS = True
MQTT_USERNAME = 'trancon2'
MQTT_PASSWORD = '123'
MQTT_TOPIC_DROWSY = "/drowsy"

# Model path - using only Keras
KERAS_MODEL_PATH = 'models/densenet201.keras'
FULL_MODEL_PATH = os.path.join('C:', os.sep, 'Users', 'tranv', 'Workspace', 'pt_iot', 'ai-server', 'models', 'densenet201.keras')

# YOLOv8 model path
YOLO_MODEL_PATH = 'models/best.pt'
FULL_YOLO_MODEL_PATH = os.path.join('C:', os.sep, 'Users', 'tranv', 'Workspace', 'pt_iot', 'ai-server', 'models', 'best.pt')

# Class names for YOLOv8 model
YOLO_CLASS_NAMES = ['Speed Limit -10-','Speed Limit -100-','Speed Limit -110-','Speed Limit -120-','Speed Limit -20-','Speed Limit -30-','Speed Limit -40-','Speed Limit -50-','Speed Limit -60-','Speed Limit -70-','Speed Limit -80-','Speed Limit -90-', 'Traffic Green', 'Traffic Red', 'Traffic Yellow']

class TrafficDetector:
    def __init__(self):
        self.model = None
        self.load_model()
    
    def load_model(self):
        """Load YOLOv8 model"""
        # Debug information
        print(f"Current working directory: {os.getcwd()}")
        absolute_path = os.path.abspath(FULL_YOLO_MODEL_PATH)
        print(f"Absolute model path: {absolute_path}")
        
        # Just check if the model file exists before trying to import ultralytics
        file_exists = os.path.exists(FULL_YOLO_MODEL_PATH) or os.path.exists(YOLO_MODEL_PATH)
        if not file_exists:
            print("ERROR: YOLOv8 model file not found!")
            logger.error("YOLOv8 model file not found!")
            return False
            
        print(f"Model file found with size: {os.path.getsize(FULL_YOLO_MODEL_PATH if os.path.exists(FULL_YOLO_MODEL_PATH) else YOLO_MODEL_PATH)} bytes")
        
        # Try to import ultralytics - if it fails, just log the error
        try:
            from ultralytics import YOLO
            have_ultralytics = True
        except ImportError as ie:
            print(f"WARNING: ultralytics module not available: {ie}")
            logger.warning(f"ultralytics module not available: {ie}")
            print("Traffic sign detection is disabled, but server will continue running")
            logger.warning("Traffic sign detection is disabled, but server will continue running")
            have_ultralytics = False
            return False
            
        # If ultralytics is available, try to load the model
        if have_ultralytics:
            model_paths_to_try = [
                FULL_YOLO_MODEL_PATH,  # Try the absolute path first
                YOLO_MODEL_PATH,       # Then try the relative path
                os.path.join(os.getcwd(), YOLO_MODEL_PATH)  # Try from current working directory
            ]
            
            for model_path in model_paths_to_try:
                if os.path.exists(model_path):
                    try:
                        print(f"Attempting to load model from: {model_path}")
                        self.model = YOLO(model_path)
                        print(f"SUCCESS: YOLOv8 model loaded from {model_path}")
                        logger.info(f"YOLOv8 model loaded successfully from {model_path}")
                        return True
                    except Exception as e:
                        full_error = str(e)
                        print(f"ERROR loading model: {full_error}")
                        logger.error(f"Error loading YOLOv8 model from {model_path}: {full_error}")
                        
            print("ERROR: Failed to load YOLOv8 model")
            logger.error("Failed to load YOLOv8 model")
        return False
    
    def detect_and_draw(self, image_data):
        """Detect objects in image and draw bounding boxes"""
        if self.model is None:
            logger.error("YOLOv8 model not loaded. Cannot perform detection.")
            # Just return the original image without processing
            return image_data
        
        try:
            # Convert binary image data to PIL Image
            pil_image = Image.open(io.BytesIO(image_data))
            
            # Convert PIL Image to OpenCV format (numpy array)
            cv_image = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
            
            # Run YOLOv8 inference
            results = self.model(cv_image)
            
            # Draw detection results on the image
            for result in results:
                boxes = result.boxes
                for i, box in enumerate(boxes):
                    # Get box coordinates, confidence and class
                    x1, y1, x2, y2 = box.xyxy[0].tolist()
                    confidence = box.conf[0].item()
                    cls_id = int(box.cls[0].item())
                    
                    # Convert to integers
                    x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
                    
                    # Get class name
                    class_name = YOLO_CLASS_NAMES[cls_id] if cls_id < len(YOLO_CLASS_NAMES) else f"Class {cls_id}"
                    
                    # Draw bounding box
                    cv2.rectangle(cv_image, (x1, y1), (x2, y2), (0, 255, 0), 2)
                    
                    # Draw label background
                    text = f"{class_name}: {confidence:.2f}"
                    text_size, _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 2)
                    cv2.rectangle(cv_image, (x1, y1 - text_size[1] - 5), (x1 + text_size[0], y1), (0, 255, 0), -1)
                    
                    # Draw label text
                    cv2.putText(cv_image, text, (x1, y1 - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 2)
            
            # Convert back to PIL Image
            pil_image_result = Image.fromarray(cv2.cvtColor(cv_image, cv2.COLOR_BGR2RGB))
            
            # Convert to binary data
            img_byte_arr = io.BytesIO()
            pil_image_result.save(img_byte_arr, format=pil_image.format or 'JPEG')
            img_byte_arr = img_byte_arr.getvalue()
            
            logger.info(f"YOLOv8 detection completed with {len(results[0].boxes)} detections")
            return img_byte_arr
            
        except Exception as e:
            logger.error(f"Error in YOLOv8 detection: {e}")
            return image_data  # Return original image on error

class DrowsinessDetector:
    def __init__(self):
        self.model = None
        self.load_model()
    
    def load_model(self):
        """Load Keras model"""
        model_paths_to_try = [
            FULL_MODEL_PATH,  # Try the absolute path first
            KERAS_MODEL_PATH  # Then try the relative path
        ]
        
        for model_path in model_paths_to_try:
            if os.path.exists(model_path):
                try:
                    self.model = load_model(model_path)
                    logger.info(f"Keras model loaded successfully from {model_path}")
                    return True
                except Exception as e:
                    logger.error(f"Error loading Keras model from {model_path}: {e}")
            else:
                logger.warning(f"Model not found at {model_path}")
        
        logger.error("Could not load model from any available path")
        return False
    
    def detect(self, image_data):
        """Detect drowsiness in image"""
        if self.model is None:
            logger.error("Model not loaded. Cannot perform detection.")
            return None
        
        try:
            # Convert binary image data to PIL Image
            image = Image.open(io.BytesIO(image_data))
            
            # Resize image to required size
            image_resized = image.resize((224, 224))
            
            # Convert to numpy array and normalize
            image_array = np.array(image_resized).astype(np.float32)
            image_array = image_array / 255.0
            
            # Add batch dimension
            image_array = np.expand_dims(image_array, axis=0)
            
            # Make prediction with TensorFlow/Keras
            predictions = self.model.predict(image_array, verbose=0)  # Set verbose=0 to reduce console output
            
            # Get class with highest probability
            class_index = np.argmax(predictions[0])
            probability = float(predictions[0][class_index])
            
            # Determine result (0=Drowsy, 1=Non-Drowsy based on the model)
            result = "Drowsy" if class_index == 0 else "Non-Drowsy"
            
            logger.info(f"Drowsiness detection result: {result} ({probability * 100:.2f}%)")
            
            return {
                "result": result,
                "class_index": int(class_index),
                "probability": probability,
                "timestamp": time.time()
            }
        except Exception as e:
            logger.error(f"Error in drowsiness detection: {e}")
            return None

# Initialize detectors
detector = DrowsinessDetector()
traffic_detector = TrafficDetector()

# Initialize MQTT client
def setup_mqtt():
    client_id = f"ai-server-{time.time()}"
    mqtt_client = mqtt.Client(client_id=client_id)
    
    # Set credentials
    if MQTT_USERNAME and MQTT_PASSWORD:
        mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    
    # Set up TLS if enabled
    if MQTT_USE_TLS:
        mqtt_client.tls_set()
    
    # Connect to broker
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
        mqtt_client.loop_start()
        logger.info(f"Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
        return mqtt_client
    except Exception as e:
        logger.error(f"Failed to connect to primary MQTT broker: {e}")
        
        # Try fallback broker
        try:
            fallback_broker = '151.106.112.215'
            fallback_port = 1883
            fallback_use_tls = False
            
            client_id = f"ai-server-fallback-{time.time()}"
            mqtt_client = mqtt.Client(client_id=client_id)
            
            if MQTT_USERNAME and MQTT_PASSWORD:
                mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
            
            mqtt_client.connect(fallback_broker, fallback_port, 60)
            mqtt_client.loop_start()
            logger.info(f"Connected to fallback MQTT broker at {fallback_broker}:{fallback_port}")
            return mqtt_client
        except Exception as e2:
            logger.error(f"Failed to connect to fallback MQTT broker: {e2}")
            
            # Try public broker as last resort
            try:
                public_broker = 'broker.emqx.io'
                public_port = 1883
                
                client_id = f"ai-server-public-{time.time()}"
                mqtt_client = mqtt.Client(client_id=client_id)
                
                mqtt_client.connect(public_broker, public_port, 60)
                mqtt_client.loop_start()
                logger.info(f"Connected to public MQTT broker at {public_broker}:{public_port}")
                return mqtt_client
            except Exception as e3:
                logger.error(f"Failed to connect to public MQTT broker: {e3}")
                return None

# Initialize MQTT client
mqtt_client = setup_mqtt()

# Socket.IO event handlers
@sio.event
def connect(sid, environ, auth=None):
    global clients_connected
    clients_connected += 1
    logger.info(f"Socket.IO client connected: {sid}")
    
    # Send last known images to newly connected client if available
    try:
        if last_esp32_image:
            sio.emit('frontcam', last_esp32_image, room=sid)
        if last_driver_image:
            sio.emit('drivercam', last_driver_image, room=sid)
    except Exception as e:
        logger.error(f"Error sending images to new client: {e}")

@sio.event
def drivercam(sid, data=None):
    global last_driver_image
    
    # Handle image request (no data sent)
    if data is None:
        try:
            logger.info(f"Client {sid} requested driver camera image")
            if last_driver_image:
                sio.emit('drivercam', last_driver_image, room=sid)
                logger.info(f"Sent driver camera image to client {sid}: {len(last_driver_image)} bytes")
                return {"status": "success", "message": "Driver camera image sent"}
            else:
                logger.info("No driver camera image available to send")
                return {"status": "error", "message": "No driver camera image available"}
        except Exception as e:
            logger.error(f"Error sending driver camera image to client {sid}: {e}")
            return {"status": "error", "message": str(e)}
    
    # Handle received image data
    try:
        logger.info(f"Received driver image from Socket.IO client {sid}, size: {len(data) if data else 'unknown'} bytes")
        last_driver_image = data
        
        # Store the image but don't process for drowsiness detection here
        # Drowsiness detection is already handled in the WebSocket handler
        
        # Forward binary buffer directly to all other clients
        sio.emit('drivercam', data, skip_sid=sid)
        return {"status": "success", "message": "Driver camera image received"}
    except Exception as e:
        logger.error(f"Error processing driver image from client {sid}: {e}")
        return {"status": "error", "message": str(e)}

@sio.event
def frontcam(sid):
    try:
        logger.info(f"Client {sid} requested front camera image")
        if last_esp32_image:
            sio.emit('frontcam', last_esp32_image, room=sid)
            logger.info(f"Sent front camera image to client {sid}: {len(last_esp32_image)} bytes")
            return {"status": "success", "message": "Front camera image sent"}
        else:
            logger.info("No front camera image available to send")
            return {"status": "error", "message": "No front camera image available"}
    except Exception as e:
        logger.error(f"Error sending front camera image to client {sid}: {e}")
        return {"status": "error", "message": str(e)}

@sio.event
def disconnect(sid):
    global clients_connected
    clients_connected -= 1
    logger.info(f"Socket.IO client disconnected: {sid}")

# WebSocket handlers for different camera endpoints
@websocket.WebSocketWSGI
def esp32_camera_handler(ws):
    global last_esp32_image
    logger.info("New ESP32 camera WebSocket connection established")
    
    # If we already have an image, send it to the new client immediately
    if last_esp32_image:
        try:
            ws.send(last_esp32_image)
            logger.info(f"Sent last known image to new WebSocket client: {len(last_esp32_image)} bytes")
        except Exception as e:
            logger.error(f"Error sending last image to new client: {e}")
    
    try:
        while True:
            # Receive binary data from ESP32 WebSocket client
            message = ws.wait()
            if message is None:
                break
            
            # Log message size
            logger.info(f"Received image from ESP32 camera: {len(message)} bytes")
            
            # Process image with YOLOv8 - Detect objects and draw bounding boxes
            # Only if the model is available
            if traffic_detector.model is not None:
                processed_image = traffic_detector.detect_and_draw(message)
                last_esp32_image = processed_image
            else:
                # Skip detection if model isn't loaded
                logger.warning("Skipping traffic detection (model not available)")
                last_esp32_image = message
            
            # Forward processed or original image data to all Socket.IO clients
            sio.emit('frontcam', last_esp32_image)
    except Exception as e:
        logger.error(f"ESP32 camera WebSocket error: {e}")
    finally:
        logger.info("ESP32 camera WebSocket connection closed")

@websocket.WebSocketWSGI
def driver_camera_handler(ws):
    global last_driver_image
    logger.info("New driver camera WebSocket connection established")
    try:
        while True:
            # Receive binary data from driver camera WebSocket client
            message = ws.wait()
            if message is None:
                break
            
            # Log message size
            logger.info(f"Received image from driver camera: {len(message)} bytes")
            
            # Store the image for new clients
            last_driver_image = message
            
            # Process image for drowsiness detection
            drowsiness_result = detector.detect(message)
            
            # Send drowsiness result via Socket.IO for the Flutter app
            if drowsiness_result:
                try:
                    sio.emit('drowsy', drowsiness_result)
                    logger.info(f"Emitted drowsiness result via Socket.IO: {drowsiness_result['result']} ({drowsiness_result['probability'] * 100:.2f}%)")
                except Exception as e:
                    logger.error(f"Error emitting drowsiness result via Socket.IO: {e}")
            
            # Forward binary image data to all Socket.IO clients
            sio.emit('drivercam', message)
    except Exception as e:
        logger.error(f"Driver camera WebSocket error: {e}")
    finally:
        logger.info("Driver camera WebSocket connection closed")

def get_websocket_handler_by_path(path):
    # Parse path to get the correct handler
    if path == '/frontcam':
        logger.info("Routing to ESP32 camera handler")
        return esp32_camera_handler
    elif path == '/drivercam':
        logger.info("Routing to driver camera handler")
        return driver_camera_handler
    else:
        logger.error(f"Unknown WebSocket path: {path}")
        return None

# Server startup section
if __name__ == '__main__':
    # Check if this is a restart attempt
    is_restart = '--restart' in sys.argv
    
    # Add file watching for auto-restart on changes
    class FileChangeHandler(FileSystemEventHandler):
        def on_modified(self, event):
            # Only watch the main script
            if event.src_path.endswith('main.py'):
                logger.info(f"File {event.src_path} has been modified. Restarting server...")
                # Restart the script with the same arguments plus a restart flag
                args = [sys.executable] + sys.argv + ['--restart']
                subprocess.Popen(args)
                os._exit(0)  # Exit the current process
    
    # Only set up file watching if not already in a restart
    if not is_restart:
        try:
            observer = Observer()
            current_dir = os.path.dirname(os.path.abspath(__file__))
            observer.schedule(FileChangeHandler(), current_dir, recursive=False)
            observer.start()
            logger.info("File watcher started - server will auto-restart on changes")
        except Exception as e:
            logger.error(f"Failed to start file watcher: {e}")
    
    # Use port 4001 for Socket.IO server
    socketio_port = 4001
    # Use port 8887 for WebSocket server (matching ESP32 client configuration)
    websocket_port = 8887
    
    # Create dispatcher to handle both WebSocket and Socket.IO
    def dispatcher(environ, start_response):
        path = environ['PATH_INFO']
        if path in ['/frontcam', '/drivercam']:
            handler = get_websocket_handler_by_path(path)
            if handler:
                return handler(environ, start_response)
        return app(environ, start_response)
    
    logger.info(f"Starting Socket.IO server on port {socketio_port}")
    logger.info(f"Starting WebSocket server on port {websocket_port}")
    logger.info(f"WebSocket routes: /frontcam (ESP32 camera), /drivercam (driver camera)")
    if is_restart:
        logger.info("This is a restart instance")
    
    # Clean up when the program exits
    try:
        # Start Socket.IO server
        try:
            socketio_server = eventlet.listen(('', socketio_port))
            eventlet.spawn(eventlet.wsgi.server, socketio_server, app)
            logger.info(f"Socket.IO server started successfully on port {socketio_port}")
        except OSError as e:
            logger.error(f"Failed to start Socket.IO server on port {socketio_port}: {e}")
            logger.info("Trying alternate port for Socket.IO server...")
            socketio_port = 4002  # Try an alternate port
            try:
                socketio_server = eventlet.listen(('', socketio_port))
                eventlet.spawn(eventlet.wsgi.server, socketio_server, app)
                logger.info(f"Socket.IO server started successfully on alternate port {socketio_port}")
            except OSError as e:
                logger.error(f"Failed to start Socket.IO server on alternate port {socketio_port}: {e}")
                raise
        
        # Start WebSocket server
        try:
            websocket_server = eventlet.listen(('', websocket_port))
            eventlet.wsgi.server(websocket_server, dispatcher)
        except OSError as e:
            logger.error(f"Failed to start WebSocket server on port {websocket_port}: {e}")
            logger.info("Trying alternate port for WebSocket server...")
            websocket_port = 8888  # Try an alternate port
            try:
                websocket_server = eventlet.listen(('', websocket_port))
                eventlet.wsgi.server(websocket_server, dispatcher)
            except OSError as e:
                logger.error(f"Failed to start WebSocket server on alternate port {websocket_port}: {e}")
                raise
    finally:
        # Disconnect MQTT client when the program exits
        if mqtt_client:
            mqtt_client.loop_stop()
            mqtt_client.disconnect()
        
        # Stop the file observer if it was started
        if not is_restart and 'observer' in locals():
            try:
                observer.stop()
                observer.join()
                logger.info("File watcher stopped")
            except Exception as e:
                logger.error(f"Error stopping file watcher: {e}")
