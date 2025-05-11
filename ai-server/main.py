import socketio
import eventlet
from eventlet import websocket
import logging
import base64

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Socket.IO setup - configure to handle binary data
sio = socketio.Server(cors_allowed_origins='*', binary=True)
app = socketio.WSGIApp(sio)

# Global variables
clients_connected = 0
last_esp32_image = None
last_driver_image = None

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
    # Check if this is a request for the latest image (no data sent)
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
    else:
        # Handle received image data
        try:
            logger.info(f"Received driver image from Socket.IO client {sid}, size: {len(data) if data else 'unknown'} bytes")
            last_driver_image = data
            # Forward binary buffer directly to all other clients
            sio.emit('drivercam', data, skip_sid=sid)
            return {"status": "success", "message": "Driver camera image received"}
        except Exception as e:
            logger.error(f"Error processing driver image from client {sid}: {e}")
            return {"status": "error", "message": str(e)}

@sio.event
def frontcam(sid):
    """Event handler to send the latest front camera image to the requesting client on demand"""
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
        print(environ)
        print(path)
        if path in ['/frontcam', '/drivercam']:
            handler = get_websocket_handler_by_path(path)
            if handler:
                return handler(environ, start_response)
        return app(environ, start_response)
    
    logger.info(f"Starting Socket.IO server on port {socketio_port}")
    logger.info(f"Starting WebSocket server on port {websocket_port}")
    logger.info(f"WebSocket routes: /frontcam (ESP32 camera), /drivercam (driver camera)")
    
    # Start Socket.IO server
    socketio_server = eventlet.listen(('', socketio_port))
    eventlet.spawn(eventlet.wsgi.server, socketio_server, app)
    
    # Start WebSocket server
    websocket_server = eventlet.listen(('', websocket_port))
    eventlet.wsgi.server(websocket_server, dispatcher)
