import os
import io
import time
import json
import logging
import numpy as np
from PIL import Image
import paho.mqtt.client as mqtt
import onnxruntime as ort
import argparse

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# MQTT Configuration from Flutter app config
MQTT_BROKER = 'fd66ecb3.ala.asia-southeast1.emqxsl.com'
MQTT_PORT = 8883
MQTT_USE_TLS = True
MQTT_USERNAME = 'trancon2'
MQTT_PASSWORD = '123'
MQTT_TOPIC_DROWSY = "/drowsy"

# ONNX Model path
ONNX_MODEL_PATH = 'models/densenet201.onnx'

class DrowsinessDetector:
    def __init__(self, model_path):
        self.model = None
        self.model_path = model_path
        self.load_model()
        
    def load_model(self):
        """Load ONNX model"""
        if not os.path.exists(self.model_path):
            logger.error(f"Model not found at {self.model_path}")
            logger.error("Please convert the Keras model to ONNX format first.")
            logger.error("Use a Python 3.10 environment to run: python convert_model_standalone.py")
            return False
            
        try:
            self.model = ort.InferenceSession(self.model_path)
            logger.info(f"ONNX model loaded successfully from {self.model_path}")
            return True
        except Exception as e:
            logger.error(f"Error loading ONNX model: {e}")
            return False
    
    def detect_from_file(self, image_path):
        """Detect drowsiness in image file"""
        try:
            # Load image from file
            image = Image.open(image_path)
            return self.detect_from_image(image)
        except Exception as e:
            logger.error(f"Error loading image file: {e}")
            return None
    
    def detect_from_image(self, image):
        """Detect drowsiness in PIL Image"""
        if self.model is None:
            logger.error("Model not loaded. Cannot perform detection.")
            return None
        
        try:
            # Resize image to required size
            image_resized = image.resize((224, 224))
            
            # Convert to numpy array and normalize
            image_array = np.array(image_resized).astype(np.float32)
            image_array = image_array / 255.0
            
            # Add batch dimension
            image_array = np.expand_dims(image_array, axis=0)
            
            # Get input and output names
            input_name = self.model.get_inputs()[0].name
            output_name = self.model.get_outputs()[0].name
            
            # Make prediction with ONNX Runtime
            predictions = self.model.run([output_name], {input_name: image_array})[0]
            
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

def setup_mqtt():
    """Set up MQTT client with fallback options"""
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

def process_image_directory(detector, directory, mqtt_client=None, interval=1.0):
    """Process all images in a directory continuously and send results to MQTT"""
    if not os.path.exists(directory):
        logger.error(f"Directory not found: {directory}")
        return
    
    while True:
        try:
            # Get all image files
            image_files = [f for f in os.listdir(directory) 
                          if f.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp'))]
            
            if not image_files:
                logger.warning(f"No image files found in {directory}")
                time.sleep(5)
                continue
                
            # Process each image
            for img_file in image_files:
                img_path = os.path.join(directory, img_file)
                logger.info(f"Processing image: {img_path}")
                
                # Detect drowsiness
                result = detector.detect_from_file(img_path)
                
                # Publish result to MQTT if available
                if result and mqtt_client:
                    try:
                        mqtt_client.publish(MQTT_TOPIC_DROWSY, json.dumps(result))
                        logger.info(f"Published result to MQTT: {result['result']} ({result['probability'] * 100:.2f}%)")
                    except Exception as e:
                        logger.error(f"Failed to publish to MQTT: {e}")
                
                # Wait before processing next image
                time.sleep(interval)
                
        except Exception as e:
            logger.error(f"Error processing directory: {e}")
            time.sleep(5)

def process_single_image(detector, image_path, mqtt_client=None):
    """Process a single image and optionally send result to MQTT"""
    if not os.path.exists(image_path):
        logger.error(f"Image file not found: {image_path}")
        return False
    
    # Detect drowsiness
    result = detector.detect_from_file(image_path)
    
    # Publish result to MQTT if available
    if result and mqtt_client:
        try:
            mqtt_client.publish(MQTT_TOPIC_DROWSY, json.dumps(result))
            logger.info(f"Published result to MQTT: {result['result']} ({result['probability'] * 100:.2f}%)")
        except Exception as e:
            logger.error(f"Failed to publish to MQTT: {e}")
    
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Drowsiness detection with ONNX Runtime")
    parser.add_argument("--model", default=ONNX_MODEL_PATH, 
                        help="Path to ONNX model file")
    parser.add_argument("--image", help="Path to a single image to process")
    parser.add_argument("--dir", help="Path to directory with images to process")
    parser.add_argument("--interval", type=float, default=1.0,
                        help="Interval between processing images in directory mode (seconds)")
    parser.add_argument("--mqtt", action="store_true", 
                        help="Enable MQTT publishing of results")
    
    args = parser.parse_args()
    
    # Check if model file exists
    if not os.path.exists(args.model):
        logger.error(f"Model file not found: {args.model}")
        logger.error("Please convert your Keras model to ONNX format first.")
        logger.error("Run 'python convert_model_standalone.py' with Python 3.10 or 3.11")
        exit(1)
    
    # Initialize detector
    detector = DrowsinessDetector(args.model)
    
    # Set up MQTT if enabled
    mqtt_client = None
    if args.mqtt:
        mqtt_client = setup_mqtt()
    
    # Process input based on arguments
    if args.image:
        # Process single image
        logger.info(f"Processing single image: {args.image}")
        result = process_single_image(detector, args.image, mqtt_client)
        if result:
            print(f"Result: {result['result']} with {result['probability'] * 100:.2f}% confidence")
    elif args.dir:
        # Process directory of images
        logger.info(f"Processing directory: {args.dir} with interval {args.interval}s")
        process_image_directory(detector, args.dir, mqtt_client, args.interval)
    else:
        # Print usage information
        logger.error("No input specified. Please provide either --image or --dir argument.")
        parser.print_help()
    
    # Disconnect MQTT client if connected
    if mqtt_client:
        mqtt_client.loop_stop()
        mqtt_client.disconnect() 