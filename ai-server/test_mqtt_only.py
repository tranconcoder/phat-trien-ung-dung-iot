import json
import time
import logging
import paho.mqtt.client as mqtt
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

def publish_test_messages(mqtt_client, count=10, interval=1.0, drowsy_prob=0.8):
    """Publish test drowsiness detection messages"""
    if not mqtt_client:
        logger.error("MQTT client not available. Cannot publish messages.")
        return False
    
    logger.info(f"Publishing {count} test messages with interval {interval}s")
    
    try:
        for i in range(count):
            # Alternate between drowsy and non-drowsy for testing
            is_drowsy = (i % 2 == 0)
            
            result = {
                "result": "Drowsy" if is_drowsy else "Non-Drowsy",
                "class_index": 0 if is_drowsy else 1,
                "probability": drowsy_prob if is_drowsy else (1.0 - drowsy_prob),
                "timestamp": time.time()
            }
            
            # Publish to MQTT
            mqtt_client.publish(MQTT_TOPIC_DROWSY, json.dumps(result))
            logger.info(f"Published test result to MQTT: {result['result']} ({result['probability'] * 100:.2f}%)")
            
            # Wait for next message
            time.sleep(interval)
            
        return True
    except Exception as e:
        logger.error(f"Error publishing test messages: {e}")
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test MQTT connection and publishing")
    parser.add_argument("--count", type=int, default=10, 
                        help="Number of test messages to publish")
    parser.add_argument("--interval", type=float, default=1.0,
                        help="Interval between messages (seconds)")
    parser.add_argument("--probability", type=float, default=0.8,
                        help="Probability value for drowsy state (0.0-1.0)")
    
    args = parser.parse_args()
    
    # Set up MQTT client
    mqtt_client = setup_mqtt()
    if not mqtt_client:
        logger.error("Failed to connect to any MQTT broker. Exiting.")
        exit(1)
    
    try:
        # Publish test messages
        success = publish_test_messages(
            mqtt_client, 
            count=args.count, 
            interval=args.interval,
            drowsy_prob=args.probability
        )
        
        if success:
            print(f"Successfully published {args.count} test messages to MQTT topic '{MQTT_TOPIC_DROWSY}'")
        else:
            print("Failed to publish test messages")
    
    finally:
        # Disconnect MQTT client
        if mqtt_client:
            mqtt_client.loop_stop()
            mqtt_client.disconnect()
            logger.info("Disconnected from MQTT broker") 