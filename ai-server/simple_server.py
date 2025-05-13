import socketio
import eventlet
from eventlet import websocket
import logging
import os
import time

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Socket.IO setup
sio = socketio.Server(cors_allowed_origins='*', binary=True)
app = socketio.WSGIApp(sio)

# Global variables
clients_connected = 0
last_driver_image = None

# Socket.IO event handlers
@sio.event
def connect(sid, environ, auth=None):
    global clients_connected
    clients_connected += 1
    logger.info(f"Socket.IO client connected: {sid}")

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
        
        # Send placeholder drowsiness data (simulated detection)
        placeholder_result = {
            "result": "Non-Drowsy",  # Default state
            "class_index": 1,
            "probability": 0.95,
            "timestamp": time.time()
        }
        
        # Emit the drowsiness result
        try:
            sio.emit('drowsy', placeholder_result)
            logger.info("Emitted simulated drowsiness result")
        except Exception as e:
            logger.error(f"Error emitting simulated result: {e}")
        
        # Forward binary buffer directly to all other clients
        sio.emit('drivercam', data, skip_sid=sid)
        return {"status": "success", "message": "Driver camera image received"}
    except Exception as e:
        logger.error(f"Error processing driver image from client {sid}: {e}")
        return {"status": "error", "message": str(e)}

@sio.event
def disconnect(sid):
    global clients_connected
    clients_connected -= 1
    logger.info(f"Socket.IO client disconnected: {sid}")

# WebSocket handler for driver camera
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
            
            # Send placeholder drowsiness data (simulated detection)
            placeholder_result = {
                "result": "Non-Drowsy",  # Default state
                "class_index": 1,
                "probability": 0.95,
                "timestamp": time.time()
            }
            
            # Randomly simulate drowsiness (10% chance)
            if time.time() % 10 < 1:  # Simple way to occasionally simulate drowsiness
                placeholder_result["result"] = "Drowsy"
                placeholder_result["class_index"] = 0
                placeholder_result["probability"] = 0.97
                logger.info("Simulating drowsiness detection")
            
            # Emit the drowsiness result
            try:
                sio.emit('drowsy', placeholder_result)
                logger.info(f"Emitted simulated drowsiness result: {placeholder_result['result']}")
            except Exception as e:
                logger.error(f"Error emitting simulated result: {e}")
            
            # Forward binary image data to all Socket.IO clients
            sio.emit('drivercam', message)
    except Exception as e:
        logger.error(f"Driver camera WebSocket error: {e}")
    finally:
        logger.info("Driver camera WebSocket connection closed")

# Create dispatcher to handle both WebSocket and Socket.IO
def dispatcher(environ, start_response):
    path = environ['PATH_INFO']
    if path == '/drivercam':
        logger.info("Routing to driver camera handler")
        return driver_camera_handler(environ, start_response)
    return app(environ, start_response)

if __name__ == '__main__':
    # Use port 4001 for Socket.IO server
    socketio_port = 4001
    # Use port 8887 for WebSocket server
    websocket_port = 8887
    
    print(f"Starting simple server...")
    print(f"Socket.IO server on port {socketio_port}")
    print(f"WebSocket server on port {websocket_port}")
    print(f"WebSocket route: /drivercam (driver camera)")
    
    try:
        # Start Socket.IO server
        socketio_server = eventlet.listen(('', socketio_port))
        eventlet.spawn(eventlet.wsgi.server, socketio_server, app)
        print(f"Socket.IO server started successfully on port {socketio_port}")
        
        # Start WebSocket server
        websocket_server = eventlet.listen(('', websocket_port))
        eventlet.wsgi.server(websocket_server, dispatcher)
    except OSError as e:
        print(f"Error starting server: {e}")
        # Try alternate ports
        try:
            socketio_port = 4002
            websocket_port = 8888
            print(f"Trying alternate ports: Socket.IO={socketio_port}, WebSocket={websocket_port}")
            
            # Start Socket.IO server on alternate port
            socketio_server = eventlet.listen(('', socketio_port))
            eventlet.spawn(eventlet.wsgi.server, socketio_server, app)
            print(f"Socket.IO server started successfully on alternate port {socketio_port}")
            
            # Start WebSocket server on alternate port
            websocket_server = eventlet.listen(('', websocket_port))
            eventlet.wsgi.server(websocket_server, dispatcher)
        except Exception as e2:
            print(f"Failed to start on alternate ports: {e2}") 