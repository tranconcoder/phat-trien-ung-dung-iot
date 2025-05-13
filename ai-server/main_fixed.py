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

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Import TensorFlow and Keras
try:
    import tensorflow as tf
    from tensorflow.keras.models import load_model
    logger.info("TensorFlow imported successfully")
except ImportError:
    logger.error("TensorFlow import failed - please install tensorflow")

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

# Initialize detector
detector = DrowsinessDetector()

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
        
        # Process image for drowsiness detection
        drowsiness_result = detector.detect(data)
        
        # Send drowsiness result to MQTT if detection was successful
        if drowsiness_result and mqtt_client:
            try:
                mqtt_client.publish(MQTT_TOPIC_DROWSY, json.dumps(drowsiness_result))
                logger.info(f"Published drowsiness result to MQTT topic '{MQTT_TOPIC_DROWSY}': {drowsiness_result['result']} ({drowsiness_result['probability'] * 100:.2f}%)")
            except Exception as e:
                logger.error(f"Error publishing to MQTT: {e}")
        
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
    try:
        while True:
            # Receive binary data from ESP32 WebSocket client
            message = ws.wait()
            if message is None:
                break
            
            # Log message size
            logger.info(f"Received image from ESP32 camera: {len(message)} bytes")
            
            # Store the image for new clients
            last_esp32_image = message
            
            # Forward binary image data to all Socket.IO clients
            sio.emit('frontcam', message)
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
            
            # Send drowsiness result to MQTT if detection was successful
            if drowsiness_result and mqtt_client:
                try:
                    mqtt_client.publish(MQTT_TOPIC_DROWSY, json.dumps(drowsiness_result))
                    logger.info(f"Published drowsiness result to MQTT topic '{MQTT_TOPIC_DROWSY}': {drowsiness_result['result']} ({drowsiness_result['probability'] * 100:.2f}%)")
                except Exception as e:
                    logger.error(f"Error publishing to MQTT: {e}")
            
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

if __name__ == '__main__':
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